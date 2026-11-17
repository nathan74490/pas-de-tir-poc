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
        if (newMode == MODE_PLACING) forward = null
        mode = newMode
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

                if (mode == MODE_PLACING) updatePlacement(camera.pose, s)

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

    /**
     * Plaque à distance fixe ([PLATE_DISTANCE]), la même pour tous les joueurs,
     * droit devant dans la direction horizontale où regarde le téléphone, au
     * niveau du sol détecté. L'utilisateur choisit seulement la direction et valide.
     */
    private fun updatePlacement(cameraPose: Pose, s: Session) {
        val camPos = cameraPose.translation
        // La caméra regarde vers -Z ; on garde la composante horizontale.
        val z = cameraPose.zAxis
        var fx = -z[0]
        var fz = -z[2]
        val len = sqrt(fx * fx + fz * fz)
        if (len < MIN_HORIZONTAL_LOOK) {
            placementSource = "look-vertical" // Téléphone pointé vers le sol ou le ciel.
            return
        }
        fx /= len
        fz /= len
        // Lissage : la plaque suit le regard sans trembler avec la main.
        forward?.let { prev ->
            // forward = sol → caméra, soit l'opposé du regard.
            val sx = -prev[0] * (1 - SMOOTHING) + fx * SMOOTHING
            val sz = -prev[2] * (1 - SMOOTHING) + fz * SMOOTHING
            val sl = sqrt(sx * sx + sz * sz)
            if (sl > 1e-3f) {
                fx = sx / sl
                fz = sz / sl
            }
        }

        val plane = s.getAllTrackables(Plane::class.java)
            .filter {
                it.trackingState == TrackingState.TRACKING && it.subsumedBy == null &&
                    it.type == Plane.Type.HORIZONTAL_UPWARD_FACING
            }
            .maxByOrNull { it.extentX * it.extentZ }
        val groundY = plane?.centerPose?.ty() ?: (camPos[1] - DEFAULT_EYE_HEIGHT)
        placementSource = if (plane != null) "fixed" else "fixed-no-plane"

        val ground = floatArrayOf(camPos[0] + fx * PLATE_DISTANCE, groundY, camPos[2] + fz * PLATE_DISTANCE)
        previewGround = ground
        // La plaque fait face à l'utilisateur : axe horizontal sol → caméra.
        forward = floatArrayOf(-fx, 0f, -fz)

        if (confirmRequested) {
            confirmRequested = false
            anchor?.detach()
            anchor = s.createAnchor(Pose.makeTranslation(ground[0], ground[1], ground[2]))
            mode = MODE_ANCHORED
        }
    }

    /** Coins de la plaque (HG, HD, BD, BG) et pieds (G, D), en pixels écran. */
    private fun projectPlate(ground: FloatArray, f: FloatArray): Pair<DoubleArray, DoubleArray>? {
        // right = up × forward, avec up = (0, 1, 0).
        val rx = f[2]
        val rz = -f[0]
        val w = PLATE_WIDTH
        // Même ratio que la rangée de cibles dessinée côté Flutter (PlateGeometry : 84/356).
        val h = PLATE_WIDTH * 84f / 356f
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

        /**
         * Distance de la plaque (m), identique pour tous : à 5 m, la rangée de
         * 2,6 m occupe à peu près la largeur de la maquette (356 px sur 390).
         */
        private const val PLATE_DISTANCE = 5f

        /** Hauteur des yeux supposée si aucun plan n'est détecté (m). */
        private const val DEFAULT_EYE_HEIGHT = 1.4f

        /** En dessous, le téléphone vise trop à la verticale pour donner une direction. */
        private const val MIN_HORIZONTAL_LOOK = 0.2f

        /** Part du nouveau regard prise à chaque image (lissage de la direction). */
        private const val SMOOTHING = 0.15f

        /** Plaque virtuelle : 2,6 m de large, posée sur des pieds de 80 cm. */
        private const val PLATE_WIDTH = 2.6f
        private const val LEG_HEIGHT = 0.8f
    }
}
