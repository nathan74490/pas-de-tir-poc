package com.alpvengers.pas_de_tir_poc.gyro

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Canaux Flutter ↔ capteurs d'orientation, pour le pas de tir au gyroscope
 * (appareils sans ARCore). Chaque événement est la matrice de rotation 3×3
 * appareil → monde (ligne par ligne) ; la visée est calculée côté Dart.
 */
object GyroBridge {
    private const val METHODS = "alpvengers/gyro"
    private const val ROTATION = "alpvengers/gyro/rotation"

    fun register(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

        // GAME_ROTATION_VECTOR : gyroscope + accéléromètre, sans boussole (pas de
        // sauts dus au magnétisme). Le gyroscope physique est exigé : sans lui,
        // certains appareils le simulent avec l'accéléromètre, inutilisable pour viser.
        fun rotationSensor(): Sensor? {
            if (sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE) == null) return null
            return sensors.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
                ?: sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        }

        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(rotationSensor() != null)
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, ROTATION).setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: SensorEventListener? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val sensor = rotationSensor() ?: return events.error("gyro", "unavailable", null)
                val matrix = FloatArray(9)
                listener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        // Certains appareils envoient 5 valeurs, refusées par getRotationMatrixFromVector.
                        SensorManager.getRotationMatrixFromVector(matrix, event.values.copyOf(minOf(4, event.values.size)))
                        events.success(DoubleArray(9) { matrix[it].toDouble() })
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                }
                sensors.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { sensors.unregisterListener(it) }
                listener = null
            }
        })
    }
}
