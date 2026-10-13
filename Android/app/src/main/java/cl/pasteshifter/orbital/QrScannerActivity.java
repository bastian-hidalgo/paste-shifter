package cl.pasteshifter.orbital;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.MeteringRectangle;
import android.media.Image;
import android.media.ImageReader;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Handler;
import android.util.Size;
import android.view.Surface;
import android.view.TextureView;
import android.graphics.Rect;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.ReaderException;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Camera2 QR reader. ZXing Core decodes frames locally without a service SDK. */
public final class QrScannerActivity extends Activity {
    static final String EXTRA_QR = "cl.pasteshifter.orbital.QR_JSON";
    private static final int CAMERA_PERMISSION_REQUEST = 4107;

    private final AtomicBoolean processingFrame = new AtomicBoolean(false);
    private final AtomicBoolean resultDelivered = new AtomicBoolean(false);
    private TextureView textureView;
    private HandlerThread cameraThread;
    private Handler cameraHandler;
    private CameraDevice camera;
    private CameraCaptureSession captureSession;
    private CaptureRequest.Builder previewRequest;
    private ImageReader imageReader;
    private Surface previewSurface;
    private final MultiFormatReader scanner = new MultiFormatReader();
    private String cameraId;
    private int sensorOrientation;
    private int frameRotation;
    private Size previewSize;
    private Rect activeArray;
    private int maxAfRegions;
    private int maxAeRegions;
    private boolean supportsAutoFocus;
    private boolean supportsContinuousFocus;
    private TextView focusHint;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(0xff10131a);
        textureView = new TextureView(this);
        root.addView(textureView, new FrameLayout.LayoutParams(-1, -1));

        TextView instruction = new TextView(this);
        instruction.setText("Conecta con tu Mac\nApunta al código que aparece en Paste Shifter");
        instruction.setTextColor(0xffffffff);
        instruction.setTextSize(19);
        instruction.setTypeface(null, android.graphics.Typeface.BOLD);
        instruction.setPadding(24, 28, 24, 24);
        instruction.setBackgroundColor(0xcc211732);
        FrameLayout.LayoutParams instructionParams = new FrameLayout.LayoutParams(-1, -2);
        root.addView(instruction, instructionParams);

        focusHint = new TextView(this);
        focusHint.setText("Buscando el código…  ·  toca el QR para enfocar");
        focusHint.setTextColor(0xffffffff); focusHint.setTextSize(14); focusHint.setGravity(android.view.Gravity.CENTER);
        focusHint.setPadding(18, 14, 18, 14); focusHint.setBackgroundColor(0xaa211732);
        FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(-1, -2);
        hintParams.gravity = android.view.Gravity.BOTTOM; hintParams.bottomMargin = 92;
        root.addView(focusHint, hintParams);

        Button cancel = new Button(this);
        cancel.setText("Cancelar");
        cancel.setOnClickListener(v -> finish());
        FrameLayout.LayoutParams cancelParams = new FrameLayout.LayoutParams(-1, -2);
        cancelParams.gravity = android.view.Gravity.BOTTOM;
        cancelParams.setMargins(24, 12, 24, 28);
        root.addView(cancel, cancelParams);
        setContentView(root);

        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.POSSIBLE_FORMATS, Collections.singletonList(BarcodeFormat.QR_CODE));
        hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
        hints.put(DecodeHintType.CHARACTER_SET, "UTF-8");
        scanner.setHints(hints);
        textureView.setSurfaceTextureListener(surfaceListener);
        textureView.setOnTouchListener((view, event) -> {
            if (event.getAction() == android.view.MotionEvent.ACTION_UP) {
                if (focusHint != null) focusHint.setText("Enfocando…");
                triggerFocusAt(event.getX(), event.getY());
                new Handler(getMainLooper()).postDelayed(() -> {
                    if (focusHint != null && !isFinishing()) focusHint.setText("Buscando el código…  ·  toca el QR para enfocar");
                }, 900);
            }
            return true;
        });
    }

    @Override protected void onResume() {
        super.onResume();
        startCameraThread();
        if (textureView.isAvailable()) openCamera();
        else textureView.setSurfaceTextureListener(surfaceListener);
    }

    @Override protected void onPause() {
        closeCamera();
        stopCameraThread();
        super.onPause();
    }

    @Override protected void onDestroy() {
        scanner.reset();
        super.onDestroy();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_PERMISSION_REQUEST && grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            openCamera();
        } else if (requestCode == CAMERA_PERMISSION_REQUEST) {
            Toast.makeText(this, "Se necesita la cámara para leer el QR de emparejamiento.", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    private final TextureView.SurfaceTextureListener surfaceListener = new TextureView.SurfaceTextureListener() {
        @Override public void onSurfaceTextureAvailable(SurfaceTexture surface, int width, int height) {
            openCamera();
        }
        @Override public void onSurfaceTextureSizeChanged(SurfaceTexture surface, int width, int height) {}
        @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture surface) { return true; }
        @Override public void onSurfaceTextureUpdated(SurfaceTexture surface) {}
    };

    private void openCamera() {
        if (isFinishing() || camera != null || resultDelivered.get()) return;
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
            return;
        }
        try {
            CameraManager manager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (manager == null) throw new IllegalStateException("Camera unavailable");
            cameraId = chooseBackCamera(manager);
            CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
            int[] afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
            supportsAutoFocus = contains(afModes, CaptureRequest.CONTROL_AF_MODE_AUTO);
            supportsContinuousFocus = contains(afModes, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            activeArray = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
            Integer afRegions = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF);
            Integer aeRegions = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE);
            maxAfRegions = afRegions == null ? 0 : afRegions;
            maxAeRegions = aeRegions == null ? 0 : aeRegions;
            sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
            frameRotation = calculateFrameRotation(sensorOrientation, getWindowManager().getDefaultDisplay().getRotation());
            android.hardware.camera2.params.StreamConfigurationMap map =
                    characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            previewSize = chooseSize(map.getOutputSizes(SurfaceTexture.class));
            Size readerSize = chooseSize(map.getOutputSizes(android.graphics.ImageFormat.YUV_420_888));
            imageReader = ImageReader.newInstance(readerSize.getWidth(), readerSize.getHeight(),
                    android.graphics.ImageFormat.YUV_420_888, 2);
            imageReader.setOnImageAvailableListener(this::processFrame, cameraHandler);
            if (textureView.isAvailable()) {
                textureView.getSurfaceTexture().setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
            }
            manager.openCamera(cameraId, cameraStateCallback, cameraHandler);
        } catch (SecurityException e) {
            finish();
        } catch (Exception e) {
            Toast.makeText(this, "No se pudo abrir la cámara.", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    private String chooseBackCamera(CameraManager manager) throws CameraAccessException {
        String selected = null;
        float bestFocalDistance = Float.MAX_VALUE;
        for (String id : manager.getCameraIdList()) {
            CameraCharacteristics info = manager.getCameraCharacteristics(id);
            Integer facing = info.get(CameraCharacteristics.LENS_FACING);
            if (facing == null || facing != CameraCharacteristics.LENS_FACING_BACK) continue;
            int[] modes = info.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES);
            boolean autofocus = contains(modes, CaptureRequest.CONTROL_AF_MODE_AUTO)
                    || contains(modes, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            if (!autofocus) continue;
            float[] focalLengths = info.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
            if (focalLengths == null || focalLengths.length == 0) continue;
            // Phone ultrawide modules are usually ~2 mm; the main rear module is
            // typically around 4–7 mm. Prefer that lens and require autofocus.
            float nearestMainLens = Float.MAX_VALUE;
            for (float focal : focalLengths) nearestMainLens = Math.min(nearestMainLens, Math.abs(focal - 5.0f));
            if (nearestMainLens < bestFocalDistance) { bestFocalDistance = nearestMainLens; selected = id; }
        }
        if (selected != null) return selected;
        throw new IllegalStateException("No back camera");
    }

    private static boolean contains(int[] values, int target) {
        if (values == null) return false;
        for (int value : values) if (value == target) return true;
        return false;
    }

    private static Size chooseSize(Size[] sizes) {
        if (sizes == null || sizes.length == 0) return new Size(640, 480);
        return Arrays.stream(sizes)
                .filter(size -> size.getWidth() <= 1280 && size.getHeight() <= 960)
                .min((a, b) -> Integer.compare(b.getWidth() * b.getHeight(), a.getWidth() * a.getHeight()))
                .orElse(sizes[0]);
    }

    private static int calculateFrameRotation(int sensor, int displayRotation) {
        int[] degrees = {0, 90, 180, 270};
        return ((sensor - degrees[displayRotation]) % 360 + 360) % 360;
    }

    private final CameraDevice.StateCallback cameraStateCallback = new CameraDevice.StateCallback() {
        @Override public void onOpened(CameraDevice device) {
            camera = device;
            createPreviewSession();
        }
        @Override public void onDisconnected(CameraDevice device) { device.close(); camera = null; }
        @Override public void onError(CameraDevice device, int error) {
            device.close(); camera = null;
            if (!isFinishing()) finish();
        }
    };

    private void createPreviewSession() {
        try {
            SurfaceTexture texture = textureView.getSurfaceTexture();
            if (texture == null || camera == null || imageReader == null) return;
            texture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
            if (previewSurface != null) previewSurface.release();
            previewSurface = new Surface(texture);
            CaptureRequest.Builder request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            request.addTarget(previewSurface);
            request.addTarget(imageReader.getSurface());
            previewRequest = request;
            camera.createCaptureSession(Arrays.asList(previewSurface, imageReader.getSurface()),
                    new CameraCaptureSession.StateCallback() {
                        @Override public void onConfigured(CameraCaptureSession session) {
                            if (camera == null) { session.close(); return; }
                            captureSession = session;
                            try {
                                request.set(CaptureRequest.CONTROL_AF_MODE, supportsContinuousFocus
                                        ? CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                                        : CaptureRequest.CONTROL_AF_MODE_AUTO);
                                request.set(CaptureRequest.CONTROL_AF_TRIGGER,
                                        CaptureRequest.CONTROL_AF_TRIGGER_IDLE);
                                // Start the live preview first so the autofocus system has
                                // image frames before receiving its one-shot focus trigger.
                                session.setRepeatingRequest(request.build(), null, cameraHandler);
                                cameraHandler.postDelayed(QrScannerActivity.this::triggerFocus, 350);
                            } catch (CameraAccessException e) {
                                finish();
                            }
                        }
                        @Override public void onConfigureFailed(CameraCaptureSession session) { finish(); }
                    }, cameraHandler);
        } catch (CameraAccessException e) {
            finish();
        }
    }

    private void triggerFocus() {
        triggerFocusAt(textureView.getWidth() / 2f, textureView.getHeight() / 2f);
    }

    private void triggerFocusAt(float viewX, float viewY) {
        CameraCaptureSession session = captureSession;
        CaptureRequest.Builder request = previewRequest;
        if (session == null || request == null || camera == null || cameraHandler == null || isFinishing()) return;
        try {
            if (activeArray != null && activeArray.width() > 0 && activeArray.height() > 0) {
                float nx = Math.max(0.05f, Math.min(0.95f, viewX / Math.max(1f, textureView.getWidth())));
                float ny = Math.max(0.05f, Math.min(0.95f, viewY / Math.max(1f, textureView.getHeight())));
                int sensorX = activeArray.left + Math.round(nx * activeArray.width());
                int sensorY = activeArray.top + Math.round(ny * activeArray.height());
                int side = Math.max(80, Math.min(activeArray.width(), activeArray.height()) / 8);
                Rect focus = new Rect(Math.max(activeArray.left, sensorX - side / 2),
                        Math.max(activeArray.top, sensorY - side / 2),
                        Math.min(activeArray.right, sensorX + side / 2),
                        Math.min(activeArray.bottom, sensorY + side / 2));
                MeteringRectangle[] region = {new MeteringRectangle(focus, MeteringRectangle.METERING_WEIGHT_MAX)};
                if (maxAfRegions > 0) request.set(CaptureRequest.CONTROL_AF_REGIONS, region);
                if (maxAeRegions > 0) request.set(CaptureRequest.CONTROL_AE_REGIONS, region);
            }
            request.set(CaptureRequest.CONTROL_AF_MODE, supportsAutoFocus
                    ? CaptureRequest.CONTROL_AF_MODE_AUTO : CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START);
            session.capture(request.build(), new CameraCaptureSession.CaptureCallback() {
                @Override public void onCaptureCompleted(CameraCaptureSession completedSession,
                        CaptureRequest completedRequest,
                        android.hardware.camera2.TotalCaptureResult result) {
                    if (camera == null || captureSession != completedSession || previewRequest != request) return;
                    cameraHandler.postDelayed(() -> restoreContinuousFocus(completedSession, request), 650);
                }
            }, cameraHandler);
        } catch (CameraAccessException ignored) {
            // Keep the preview available; the device may already be focusing continuously.
        }
    }

    private void restoreContinuousFocus(CameraCaptureSession completedSession, CaptureRequest.Builder request) {
        if (camera == null || captureSession != completedSession || previewRequest != request || isFinishing()) return;
        try {
            request.set(CaptureRequest.CONTROL_AF_MODE, supportsContinuousFocus
                    ? CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE : CaptureRequest.CONTROL_AF_MODE_AUTO);
            request.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE);
            completedSession.setRepeatingRequest(request.build(), null, cameraHandler);
        } catch (CameraAccessException ignored) { finish(); }
    }

    private void processFrame(ImageReader reader) {
        Image image = reader.acquireLatestImage();
        if (image == null) return;
        if (!processingFrame.compareAndSet(false, true)) { image.close(); return; }
        String qrValue = null;
        try {
            android.media.Image.Plane plane = image.getPlanes()[0];
            int width = image.getWidth();
            int height = image.getHeight();
            java.nio.ByteBuffer buffer = plane.getBuffer();
            byte[] luminance = new byte[width * height];
            int start = buffer.position();
            int rowStride = plane.getRowStride();
            int pixelStride = plane.getPixelStride();
            for (int y = 0; y < height; y++) {
                int row = start + y * rowStride;
                for (int x = 0; x < width; x++) {
                    luminance[y * width + x] = buffer.get(row + x * pixelStride);
                }
            }
            RotatedLuminance frame = rotate(luminance, width, height, frameRotation);
            PlanarYUVLuminanceSource source = new PlanarYUVLuminanceSource(
                    frame.bytes, frame.width, frame.height, 0, 0, frame.width, frame.height, false);
            Result result = scanner.decodeWithState(new BinaryBitmap(new HybridBinarizer(source)));
            String value = result.getText();
            if (value != null && value.startsWith("{")) qrValue = value;
        } catch (ReaderException | RuntimeException ignored) {
            // Most camera frames do not contain a readable QR code.
        } finally {
            try { scanner.reset(); }
            finally {
                image.close();
                processingFrame.set(false);
            }
        }
        if (qrValue != null && !resultDelivered.get()) deliverResult(qrValue);
    }

    private static RotatedLuminance rotate(byte[] source, int width, int height, int degrees) {
        if (degrees == 0) return new RotatedLuminance(source, width, height);
        int outputWidth = degrees == 90 || degrees == 270 ? height : width;
        int outputHeight = degrees == 90 || degrees == 270 ? width : height;
        byte[] output = new byte[source.length];
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int targetX;
                int targetY;
                if (degrees == 90) { targetX = height - 1 - y; targetY = x; }
                else if (degrees == 180) { targetX = width - 1 - x; targetY = height - 1 - y; }
                else if (degrees == 270) { targetX = y; targetY = width - 1 - x; }
                else throw new IllegalArgumentException("Unsupported camera rotation");
                output[targetY * outputWidth + targetX] = source[y * width + x];
            }
        }
        return new RotatedLuminance(output, outputWidth, outputHeight);
    }

    private static final class RotatedLuminance {
        final byte[] bytes;
        final int width;
        final int height;
        RotatedLuminance(byte[] bytes, int width, int height) {
            this.bytes = bytes; this.width = width; this.height = height;
        }
    }

    private void deliverResult(String rawValue) {
        if (!resultDelivered.compareAndSet(false, true)) return;
        runOnUiThread(() -> {
            Intent result = new Intent();
            result.putExtra(EXTRA_QR, rawValue);
            setResult(RESULT_OK, result);
            finish();
        });
    }

    private void closeCamera() {
        if (captureSession != null) { captureSession.close(); captureSession = null; }
        if (camera != null) { camera.close(); camera = null; }
        if (imageReader != null) { imageReader.close(); imageReader = null; }
        if (previewSurface != null) { previewSurface.release(); previewSurface = null; }
        previewRequest = null;
    }

    private void startCameraThread() {
        if (cameraThread != null) return;
        cameraThread = new HandlerThread("OrbitalQrCamera");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());
    }

    private void stopCameraThread() {
        if (cameraThread == null) return;
        cameraThread.quitSafely();
        try { cameraThread.join(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        cameraThread = null;
        cameraHandler = null;
    }
}
