package com.alpvengers.pas_de_tir_poc.arcore

import android.app.Activity
import android.graphics.Bitmap
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Vue ARCore : flux caméra + détection des plans horizontaux + ancre de la
 * plaque de tir. La plaque n'est pas rendue ici : chaque frame, ses coins sont
 * projetés à l'écran et envoyés à Flutter, qui la dessine en surimpression.
 */
class ArCoreView(private val activity: Activity) : PlatformView, GLSurfaceView.Renderer {

    private val surface = GLSurfaceView(activity).apply {
        preserveEGLContextOnPause = true
        setEGLContextClientVersion(2)
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        setRenderer(this@ArCoreView)
        renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
    }

    private val main = Handler(Looper.getMainLooper())
    private val background = BackgroundRenderer()
    private var session: Session? = null
    private var resumed = false
    private var viewWidth = 0
    private var viewHeight = 0

    // Commandes venant de Flutter (thread principal), lues par le thread GL.
    @Volatile private var mode = MODE_SCANNING
    @Volatile private var placementX = -1f
    @Volatile private var placementY = -1f
    @Volatile private var confirmRequested = false
    @Volatile private var pendingCapture: MethodChannel.Result? = null

    // État de placement (thread GL).
    private var anchor: Anchor? = null
    private var previewGround: FloatArray? = null
    private var forward: FloatArray? = null

    private val view = FloatArray(16)
    private val proj = FloatArray(16)
    private val viewProj = FloatArray(16)
    private val tmpIn = FloatArray(4)
    private val tmpOut = FloatArray(4)
    private val invViewProj = FloatArray(16)
    private var placementSource = "none"

    /** Un seul envoi vers Flutter en attente à la fois (évite de saturer le thread principal). */
    private val emitPending = AtomicBoolean(false)
    private var lastLogMs = 0L

    init {
        // Une seule session ARCore à la fois : libère la caméra de l'ancienne vue.
        ArCoreBridge.activeView?.dispose()
        try {
            session = Session(activity).also { s ->
                val config = Config(s).apply {
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    focusMode = Config.FocusMode.AUTO
                    // BLOCKING : un rendu par image caméra, pas de surcharge du GPU/CPU.
                    updateMode = Config.UpdateMode.BLOCKING
                    lightEstimationMode = Config.LightEstimationMode.DISABLED
                }
                s.configure(config)
            }
            ArCoreBridge.activeView = this
            resume()
        } catch (e: Exception) {
            Log.e(TAG, "Création de la session ARCore impossible", e)
            main.post { ArCoreBridge.emitError(e.javaClass.simpleName) }
        }
    }

    override fun getView(): View = surface

    override fun dispose() {
        if (ArCoreBridge.activeView === this) ArCoreBridge.activeView = null
        pause()
        session?.close()
        session = null
    }

    fun resume() {
        if (resumed || session == null) return
        try {
            session?.resume()
            surface.onResume()
            resumed = true
        } catch (e: Exception) {
            Log.e(TAG, "Reprise ARCore impossible", e)
            main.post { ArCoreBridge.emitError(e.javaClass.simpleName) }
        }
    }

    fun pause() {
        if (!resumed) return
        surface.onPause()
        session?.pause()
        resumed = false
    }

    fun setMode(newMode: String) {
        if (newMode == MODE_PLACING) {
            placementX = -1f
            placementY = -1f
        }
        mode = newMode
    }

    fun setPlacementPoint(x: Float, y: Float) {
        placementX = x
        placementY = y
    }

    fun confirmPlacement() {
        confirmRequested = true
    }

    fun capture(result: MethodChannel.Result) {
        pendingCapture = result
    }

    // ─────────────────────────────── GL ───────────────────────────────

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        background.createOnGlThread()
        session?.setCameraTextureName(background.textureId)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewWidth = width
        viewHeight = height
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: 0
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.rotation
        }
        session?.setDisplayGeometry(rotation, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        try {
            val frame = s.update()
            background.draw(frame)
            val camera = frame.camera
            val data = HashMap<String, Any>()
            val tracking = camera.trackingState == TrackingState.TRACKING
            data["tracking"] = tracking
            data["failure"] = camera.trackingFailureReason.name
            data["width"] = viewWidth
            data["height"] = viewHeight

            if (tracking) {
                camera.getProjectionMatrix(proj, 0, 0.05f, 200f)
                camera.getViewMatrix(view, 0)
                Matrix.multiplyMM(viewProj, 0, proj, 0, view, 0)

                var area = 0f
                var planes = 0
                for (plane in s.getAllTrackables(Plane::class.java)) {
                    if (plane.trackingState == TrackingState.TRACKING && plane.subsumedBy == null &&
                        plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                    ) {
                        area += plane.extentX * plane.extentZ
                        planes++
                    }
                }
                data["planeArea"] = area.toDouble()
                logDiagnostics(
                    "tracking planes=$planes area=${"%.2f".format(area)} mode=$mode placement=$placementSource " +
                        "plate=${previewGround != null || anchor != null}"
                )

                if (mode != MODE_ANCHORED) data["points"] = projectedPointCloud(frame)

                val camPos = camera.pose.translation
                if (mode == MODE_PLACING) updatePlacement(frame.hitTest(placementXOr(), placementYOr()), camPos, s)

                val ground = if (mode == MODE_ANCHORED) anchor?.pose?.translation else previewGround
                val fwd = forward
                if (ground != null && fwd != null && mode != MODE_SCANNING) {
                    projectPlate(ground, fwd)?.let { (corners, feet) ->
                        data["corners"] = corners
                        data["feet"] = feet
                    }
                }
            } else {
                logDiagnostics("NOT tracking state=${camera.trackingState} reason=${camera.trackingFailureReason}")
            }
            data["mode"] = mode

            pendingCapture?.let {
                pendingCapture = null
                captureFrame(it)
            }

            if (emitPending.compareAndSet(false, true)) {
                main.post {
                    emitPending.set(false)
                    ArCoreBridge.emitFrame(data)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Frame ARCore ignorée", e)
        }
    }

    private fun logDiagnostics(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastLogMs < 1000) return
        lastLogMs = now
        Log.i(TAG, message)
    }

    private fun placementXOr() = if (placementX < 0) viewWidth / 2f else placementX
    private fun placementYOr() = if (placementY < 0) viewHeight * 0.62f else placementY

    /**
     * Position de la plaque au sol sous le point visé : hit-test ARCore dans le
     * contour d'un plan, sinon intersection du rayon de visée avec le plan
     * horizontal détecté le plus grand (contours ARCore souvent incomplets).
     */
    private fun updatePlacement(hits: List<HitResult>, camPos: FloatArray, s: Session) {
        val hit = hits.firstOrNull {
            val t = it.trackable
            t is Plane && t.type == Plane.Type.HORIZONTAL_UPWARD_FACING && t.isPoseInPolygon(it.hitPose)
        }
        val ground: FloatArray
        var plane: Plane? = null
        if (hit != null) {
            ground = hit.hitPose.translation
            placementSource = "hit"
        } else {
            plane = s.getAllTrackables(Plane::class.java)
                .filter {
                    it.trackingState == TrackingState.TRACKING && it.subsumedBy == null &&
                        it.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                }
                .maxByOrNull { it.extentX * it.extentZ }
            ground = plane?.let { rayOnPlane(placementXOr(), placementYOr(), it.centerPose.ty(), camPos) } ?: run {
                placementSource = if (plane == null) "no-plane" else "ray-miss"
                return
            }
            placementSource = "ray"
        }

        // La plaque fait face à l'utilisateur : axe horizontal sol → caméra.
        val fx = camPos[0] - ground[0]
        val fz = camPos[2] - ground[2]
        val len = sqrt(fx * fx + fz * fz)
        if (len < 1e-3f) return
        previewGround = ground
        forward = floatArrayOf(fx / len, 0f, fz / len)

        if (confirmRequested) {
            confirmRequested = false
            anchor?.detach()
            anchor = hit?.createAnchor() ?: plane!!.createAnchor(Pose.makeTranslation(ground[0], ground[1], ground[2]))
            mode = MODE_ANCHORED
        }
    }

    /** Intersection du rayon caméra passant par le point écran (x, y) avec le plan y = [planeY]. */
    private fun rayOnPlane(x: Float, y: Float, planeY: Float, camPos: FloatArray): FloatArray? {
        if (!Matrix.invertM(invViewProj, 0, viewProj, 0)) return null
        val nx = 2f * x / viewWidth - 1f
        val ny = 1f - 2f * y / viewHeight
        fun unproject(z: Float): FloatArray {
            tmpIn[0] = nx; tmpIn[1] = ny; tmpIn[2] = z; tmpIn[3] = 1f
            Matrix.multiplyMV(tmpOut, 0, invViewProj, 0, tmpIn, 0)
            return floatArrayOf(tmpOut[0] / tmpOut[3], tmpOut[1] / tmpOut[3], tmpOut[2] / tmpOut[3])
        }
        val near = unproject(-1f)
        val far = unproject(1f)
        val dx = far[0] - near[0]
        val dy = far[1] - near[1]
        val dz = far[2] - near[2]
        if (dy > -1e-4f) return null // On ne vise pas vers le sol.
        val t = (planeY - near[1]) / dy
        if (t <= 0f) return null
        val p = floatArrayOf(near[0] + dx * t, planeY, near[2] + dz * t)
        val distance = sqrt((p[0] - camPos[0]).let { it * it } + (p[2] - camPos[2]).let { it * it })
        return if (distance <= MAX_PLACEMENT_DISTANCE) p else null
    }

    /** Coins de la plaque (HG, HD, BD, BG) et pieds (G, D), en pixels écran. */
    private fun projectPlate(ground: FloatArray, f: FloatArray): Pair<DoubleArray, DoubleArray>? {
        // right = up × forward, avec up = (0, 1, 0).
        val rx = f[2]
        val rz = -f[0]
        val w = PLATE_WIDTH
        val h = PLATE_WIDTH * 0.286f
        val cy = ground[1] + LEG_HEIGHT + h / 2
        fun point(dx: Float, y: Float) = floatArrayOf(ground[0] + rx * dx, y, ground[2] + rz * dx)

        val world = listOf(
            point(-w / 2, cy + h / 2), point(w / 2, cy + h / 2),
            point(w / 2, cy - h / 2), point(-w / 2, cy - h / 2),
        )
        val corners = DoubleArray(8)
        for ((i, p) in world.withIndex()) if (!project(p, corners, i * 2)) return null
        val feet = DoubleArray(4)
        if (!project(point(-w * 0.42f, ground[1]), feet, 0)) return null
        if (!project(point(w * 0.40f, ground[1]), feet, 2)) return null
        return corners to feet
    }

    private fun project(p: FloatArray, out: DoubleArray, i: Int): Boolean {
        tmpIn[0] = p[0]; tmpIn[1] = p[1]; tmpIn[2] = p[2]; tmpIn[3] = 1f
        Matrix.multiplyMV(tmpOut, 0, viewProj, 0, tmpIn, 0)
        if (tmpOut[3] <= 1e-4f) return false
        val ndcX = tmpOut[0] / tmpOut[3]
        val ndcY = tmpOut[1] / tmpOut[3]
        out[i] = ((ndcX + 1) / 2 * viewWidth).toDouble()
        out[i + 1] = ((1 - ndcY) / 2 * viewHeight).toDouble()
        return true
    }

    private fun projectedPointCloud(frame: com.google.ar.core.Frame): DoubleArray {
        frame.acquirePointCloud().use { cloud ->
            val buf = cloud.points
            val n = buf.remaining() / 4
            val step = max(1, n / MAX_POINTS)
            val out = ArrayList<Double>(MAX_POINTS * 2)
            val p = FloatArray(3)
            val px = DoubleArray(2)
            var i = 0
            while (i < n) {
                val confidence = buf.get(i * 4 + 3)
                if (confidence > 0.2f) {
                    p[0] = buf.get(i * 4); p[1] = buf.get(i * 4 + 1); p[2] = buf.get(i * 4 + 2)
                    if (project(p, px, 0) && px[0] in 0.0..viewWidth.toDouble() && px[1] in 0.0..viewHeight.toDouble()) {
                        out.add(px[0]); out.add(px[1])
                    }
                }
                i += step
            }
            return out.toDoubleArray()
        }
    }

    /** Capture de l'image caméra courante (souvenir partageable). */
    private fun captureFrame(result: MethodChannel.Result) {
        val w = viewWidth
        val h = viewHeight
        val buffer = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        GLES20.glReadPixels(0, 0, w, h, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        thread {
            try {
                val raw = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                buffer.rewind()
                raw.copyPixelsFromBuffer(buffer)
                val flip = android.graphics.Matrix().apply { preScale(1f, -1f) }
                val bitmap = Bitmap.createBitmap(raw, 0, 0, w, h, flip, false)
                val file = File(activity.cacheDir, "pas_de_tir_ar_${System.currentTimeMillis()}.jpg")
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
                main.post { result.success(file.absolutePath) }
            } catch (e: Exception) {
                main.post { result.success(null) }
            }
        }
    }

    companion object {
        private const val TAG = "PasDeTirAR"
        const val MODE_SCANNING = "scanning"
        const val MODE_PLACING = "placing"
        const val MODE_ANCHORED = "anchored"
        private const val MAX_POINTS = 120
        private const val MAX_PLACEMENT_DISTANCE = 12f

        /** Plaque virtuelle : 2,6 m de large, posée sur des pieds de 80 cm. */
        private const val PLATE_WIDTH = 2.6f
        private const val LEG_HEIGHT = 0.8f
    }
}
