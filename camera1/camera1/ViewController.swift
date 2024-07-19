import AVFoundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

class ViewController: UIViewController {
    // Capture Session
    var session: AVCaptureSession?
    
    // Photo Output
    let output = AVCapturePhotoOutput()
    
    // Video Data Output
    let videoDataOutput = AVCaptureVideoDataOutput()
    
    // Video Preview
    let previewLayer = AVCaptureVideoPreviewLayer()
    
    // Start button
    private let startButton: UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        button.setTitle("Start", for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 25
        button.setTitleColor(.white, for: .normal)
        return button
    }()
    
    // Overlay container view
    private let overlayContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    // Blur effect view
    private let blurEffectView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        return blurEffectView
    }()
    
    // Overlay view
    private let overlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.clear
        view.layer.masksToBounds = true
        return view
    }()
    
    // Prompt label
    private let promptLabel: UILabel = {
        let label = UILabel()
        label.text = "Position your face in the frame to take a photo"
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        return label
    }()
    
    // Countdown label
    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 60, weight: .bold)
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()
    
    // Photo count
    private var photoCount = 0
    
    // Face detection request
    private var faceDetectionRequest: VNDetectFaceLandmarksRequest?
    
    // Throttle photo capture
    private var canTakePhoto = false
    
    // Face rect to maintain blur effect
    private var faceRect: CGRect?
    
    // Stored face path from the first image
    private var storedFacePath: UIBezierPath?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        setupOverlay()
        setupPromptLabel()
        setupCountdownLabel()
        setupStartButton()
        checkCameraPermissions()
        setupFaceDetection()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        
        overlayContainerView.frame = view.bounds
        blurEffectView.frame = view.bounds
        overlayView.frame = view.bounds
        
        let promptLabelY = view.frame.size.height - 150
        
        promptLabel.frame = CGRect(x: 20, y: promptLabelY, width: view.frame.width - 40, height: 60)
        countdownLabel.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        countdownLabel.center = overlayView.center
        startButton.center = CGPoint(x: view.frame.size.width / 2, y: promptLabelY + 100)
    }
    
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.setupCamera()
                }
            }
        case .restricted, .denied:
            break
        case .authorized:
            setupCamera()
        @unknown default:
            break
        }
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                if session.canAddOutput(videoDataOutput) {
                    session.addOutput(videoDataOutput)
                    videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
                }
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.session = session
                session.startRunning()
                self.session = session
            } catch {
                print(error)
            }
        }
    }
    
    private func setupOverlay() {
        view.addSubview(overlayContainerView)
        overlayContainerView.addSubview(blurEffectView)
        overlayContainerView.addSubview(overlayView)
    }
    
    private func setupPromptLabel() {
        view.addSubview(promptLabel)
    }
    
    private func setupCountdownLabel() {
        view.addSubview(countdownLabel)
    }
    
    private func setupStartButton() {
        view.addSubview(startButton)
        startButton.addTarget(self, action: #selector(didTapStartButton), for: .touchUpInside)
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { [weak self] request, error in
            guard let results = request.results as? [VNFaceObservation], let self = self else { return }
            
            DispatchQueue.main.async {
                self.handleFaceDetectionResults(results)
            }
        })
    }
    
    private func handleFaceDetectionResults(_ results: [VNFaceObservation]) {
        guard let result = results.first else {
            // No face detected
            overlayView.layer.sublayers?.removeAll()
            return
        }
        
        let faceRect = result.boundingBox
        let size = previewLayer.bounds.size
        let origin = CGPoint(x: faceRect.origin.x * size.width,
                             y: (1 - faceRect.origin.y - faceRect.size.height) * size.height)
        let convertedRect = CGRect(origin: origin,
                                   size: CGSize(width: faceRect.size.width * size.width,
                                                height: faceRect.size.height * size.height))
        
        // Update faceRect and create the blur overlay
        self.faceRect = convertedRect
        
        if photoCount == 1 {
            createFaceMask(for: result)
        } else {
            overlayView.layer.sublayers?.removeAll()
        }
        
        // Check if the face is within the mask
        if photoCount == 1, let storedFacePath = self.storedFacePath, storedFacePath.contains(CGPoint(x: convertedRect.midX, y: convertedRect.midY)) {
            startCountdown()
        } else if photoCount == 0 {
            startCountdown()
        }
    }
    
    private func createFaceMask(for faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks else { return }
        
        let facePath = UIBezierPath()
        let size = previewLayer.bounds.size
        
        // Helper function to convert normalized points to view points
        func convertPoints(_ points: [CGPoint], boundingBox: CGRect) -> [CGPoint] {
            return points.map { point in
                let x = boundingBox.origin.x * size.width + point.x * boundingBox.size.width * size.width
                let y = (1 - boundingBox.origin.y) * size.height - point.y * boundingBox.size.height * size.height
                return CGPoint(x: x, y: y)
            }
        }
        
        // Add paths for the face contour
        if let faceContour = landmarks.faceContour {
            let points = convertPoints(faceContour.normalizedPoints, boundingBox: faceObservation.boundingBox)
            for (i, point) in points.enumerated() {
                if i == 0 {
                    facePath.move(to: point)
                } else {
                    facePath.addLine(to: point)
                }
            }
            facePath.close()
        }
        
        storedFacePath = facePath
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = facePath.cgPath
        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.strokeColor = UIColor.white.cgColor
        maskLayer.lineWidth = 5
        
        overlayView.layer.sublayers?.removeAll()
        overlayView.layer.addSublayer(maskLayer)
        
        // Create a hole in the blur effect view
        let path = UIBezierPath(rect: blurEffectView.bounds)
        path.append(facePath.reversing())
        
        let blurMaskLayer = CAShapeLayer()
        blurMaskLayer.path = path.cgPath
        blurEffectView.layer.mask = blurMaskLayer
    }
    
    private func createHeadMask(for faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks else { return }
        
        let headPath = UIBezierPath()
        let size = previewLayer.bounds.size
        
        // Helper function to convert normalized points to view points
        func convertPoints(_ points: [CGPoint], boundingBox: CGRect) -> [CGPoint] {
            return points.map { point in
                let x = boundingBox.origin.x * size.width + point.x * boundingBox.size.width * size.width
                let y = (1 - boundingBox.origin.y) * size.height - point.y * boundingBox.size.height * size.height
                return CGPoint(x: x, y: y)
            }
        }
        
        // Add paths for the outer head
        if let faceContour = landmarks.faceContour {
            let points = convertPoints(faceContour.normalizedPoints, boundingBox: faceObservation.boundingBox)
            for (i, point) in points.enumerated() {
                if i == 0 {
                    headPath.move(to: point)
                } else {
                    headPath.addLine(to: point)
                }
            }
            headPath.close()
        }
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = headPath.cgPath
        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.strokeColor = UIColor.white.cgColor
        maskLayer.lineWidth = 5
        
        overlayView.layer.sublayers?.removeAll()
        overlayView.layer.addSublayer(maskLayer)
        
        // Create a hole in the blur effect view
        let path = UIBezierPath(rect: blurEffectView.bounds)
        path.append(headPath.reversing())
        
        let blurMaskLayer = CAShapeLayer()
        blurMaskLayer.path = path.cgPath
        blurEffectView.layer.mask = blurMaskLayer
    }
    
    private func startCountdown() {
        guard canTakePhoto else { return }
        canTakePhoto = false
        
        if photoCount == 0 {
            blurEffectView.isHidden = true
        }
        
        countdownLabel.isHidden = false
        countdownLabel.text = "3"
        
        var countdown = 3
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            countdown -= 1
            self.countdownLabel.text = "\(countdown)"
            if countdown == 0 {
                timer.invalidate()
                self.countdownLabel.isHidden = true
                self.didTapTakePhoto()
            }
        }
    }
    
    @objc private func didTapStartButton() {
        startButton.isHidden = true
        promptLabel.text = "Position your face in the frame to take a photo"
        promptLabel.isHidden = false
        canTakePhoto = true
    }
    
    @objc private func didTapTakePhoto() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    private func resetToStart() {
        photoCount = 0
        canTakePhoto = false
        startButton.isHidden = false
        promptLabel.isHidden = true
        faceRect = nil // Reset the faceRect to allow new detection and blur creation
        blurEffectView.layer.mask = nil
        overlayView.layer.sublayers?.removeAll()
        storedFacePath = nil
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        
        processImage(image)
    }
    
    private func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        do {
            try handler.perform([request])
            guard let mask = request.results?.first?.pixelBuffer else { return }
            
            let maskImage = CIImage(cvPixelBuffer: mask)
            let ciImage = CIImage(cgImage: cgImage)
            
            let maskScaleX = ciImage.extent.width / maskImage.extent.width
            let maskScaleY = ciImage.extent.height / maskImage.extent.height
            let scaledMaskImage = maskImage.transformed(by: .init(scaleX: maskScaleX, y: maskScaleY))
            
            let blendFilter = CIFilter.blendWithRedMask()
            blendFilter.inputImage = ciImage
            blendFilter.maskImage = scaledMaskImage
            blendFilter.backgroundImage = CIImage(color: .white).cropped(to: ciImage.extent)
            
            guard let outputImage = blendFilter.outputImage else { return }
            let context = CIContext()
            if let cgOutputImage = context.createCGImage(outputImage, from: outputImage.extent) {
                let finalImage = UIImage(cgImage: cgOutputImage)
                
                // Save the final image
                UIImageWriteToSavedPhotosAlbum(finalImage, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
                
                photoCount += 1
                
                if photoCount == 1 {
                    promptLabel.text = "Now make a face and take a second photo"
                    blurEffectView.isHidden = false
                    
                    // Reset the flag to allow another photo after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.canTakePhoto = true
                    }
                } else {
                    promptLabel.text = "Congratulations! You have completed the photo session."
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.resetToStart()
                    }
                }
            }
        } catch {
            print("Failed to process image: \(error)")
        }
    }
    
    @objc private func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("Error saving image: \(error.localizedDescription)")
        } else {
            print("Image saved successfully")
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), canTakePhoto else { return }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        
        do {
            try imageRequestHandler.perform([faceDetectionRequest].compactMap { $0 })
        } catch {
            print(error)
        }
    }
}
