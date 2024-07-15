import AVFoundation
import UIKit
import Vision

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
    
    // Oval mask properties
    private var ovalRect: CGRect = .zero
    
    // Throttle photo capture
    private var canTakePhoto = false
    
    // Face rect to maintain blur effect
    private var faceRect: CGRect?
    
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
        
        let maskHeight = view.frame.size.height * 0.7
        let maskTopY = view.frame.size.height / 2 - maskHeight / 2 - 50
        
        createOvalMask()
        
        let promptLabelY = maskTopY + maskHeight - 150
        
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
            createOvalMask()
            return
        }
        
        let faceRect = result.boundingBox
        let size = previewLayer.bounds.size
        let origin = CGPoint(x: faceRect.origin.x * size.width,
                             y: (1 - faceRect.origin.y - faceRect.size.height) * size.height)
        let convertedRect = CGRect(origin: origin,
                                   size: CGSize(width: faceRect.size.width * size.width,
                                                height: faceRect.size.height * size.height))
        
        // Set the faceRect once and create the blur overlay
        if self.faceRect == nil {
            self.faceRect = convertedRect
            createBlurOverlay(for: convertedRect)
            addReferencePoints(for: result)
        }
        
        // Check if the face is within the oval mask
        if ovalRect.contains(convertedRect) {
            startCountdown()
        }
    }
    
    private func createOvalMask() {
        let ovalPath = UIBezierPath()
        let width: CGFloat = view.frame.size.width * 0.9
        let height: CGFloat = view.frame.size.height * 0.6
        ovalRect = CGRect(x: view.frame.size.width / 2 - width / 2,
                          y: view.frame.size.height / 2 - height / 2 - 50, // 50 points above the center
                          width: width,
                          height: height)
        
        ovalPath.append(UIBezierPath(ovalIn: ovalRect))
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = ovalPath.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.strokeColor = UIColor.white.cgColor
        maskLayer.lineWidth = 5
        
        // Create a hole in the blur effect view
        let path = UIBezierPath(rect: blurEffectView.bounds)
        path.append(UIBezierPath(ovalIn: ovalRect).reversing())
        
        let blurMaskLayer = CAShapeLayer()
        blurMaskLayer.path = path.cgPath
        blurEffectView.layer.mask = blurMaskLayer
        
        overlayView.layer.sublayers?.removeAll()
        overlayView.layer.addSublayer(maskLayer)
    }
    
    private func createBlurOverlay(for faceRect: CGRect) {
        overlayView.layer.sublayers?.removeAll()
        
        let path = UIBezierPath(rect: blurEffectView.bounds)
        
        // Create an oval path around the face rect with a margin to include some space around the face
        let margin: CGFloat = 30.0
        let extendedFaceRect = faceRect.insetBy(dx: -margin, dy: -margin)
        let ovalPath = UIBezierPath(ovalIn: extendedFaceRect)
        path.append(ovalPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        
        blurEffectView.layer.mask = maskLayer
    }
    
    private func addReferencePoints(for faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks else { return }
        
        // Helper function to add a dot for a given landmark point
        func addDot(at point: CGPoint, color: UIColor) {
            let size = previewLayer.bounds.size
            let x = faceObservation.boundingBox.origin.x * size.width + point.x * faceObservation.boundingBox.width * size.width
            let y = (1 - faceObservation.boundingBox.origin.y) * size.height - point.y * faceObservation.boundingBox.height * size.height
            
            let dotLayer = CALayer()
            dotLayer.frame = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
            dotLayer.backgroundColor = color.cgColor
            dotLayer.cornerRadius = 3
            
            overlayView.layer.addSublayer(dotLayer)
        }
        
        // Add dots for the left and right eyes' outer points (approximating the ears)
        if let leftEye = landmarks.leftEye {
            addDot(at: leftEye.normalizedPoints.first!, color: .red)
        }
        if let rightEye = landmarks.rightEye {
            addDot(at: rightEye.normalizedPoints.last!, color: .red)
        }
        
        // Add dot for the nose crest (bridge of the nose)
        if let noseCrest = landmarks.noseCrest {
            addDot(at: noseCrest.normalizedPoints[1], color: .blue)
        }
    }
    
    private func startCountdown() {
        guard canTakePhoto else { return }
        canTakePhoto = false
        
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
        createOvalMask()
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        
        photoCount += 1
        
        if photoCount == 1 {
            // Save the first photo to the photo album
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
            
            promptLabel.text = "Now make a face and take a second photo"
            
            // Reset the flag to allow another photo after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.canTakePhoto = true
            }
        } else {
            // Save the second photo to the photo album
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
            
            promptLabel.text = "Congratulations! You have completed the photo session."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.resetToStart()
            }
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
