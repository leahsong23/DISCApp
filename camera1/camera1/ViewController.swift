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
    
    // Restart button
    private let restartButton: UIButton = {
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        button.setTitle("Restart", for: .normal)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 25
        button.setTitleColor(.white, for: .normal)
        button.isHidden = true
        return button
    }()
    
    // Overlay container view
    private let overlayContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
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
    
    // Stored person mask from the first image
    private var storedPersonMask: CIImage?
    
    // Stored image from the first photo
    private var storedImage: CIImage?
    
    // Person segmentation request
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        setupOverlay()
        setupPromptLabel()
        setupCountdownLabel()
        setupStartButton()
        setupRestartButton()
        checkCameraPermissions()
        setupFaceDetection()
        setupPersonSegmentation()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        
        overlayContainerView.frame = view.bounds
        overlayView.frame = view.bounds
        
        let promptLabelY = view.frame.size.height - 150
        
        promptLabel.frame = CGRect(x: 20, y: promptLabelY, width: view.frame.width - 40, height: 60)
        countdownLabel.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        countdownLabel.center = overlayView.center
        startButton.center = CGPoint(x: view.frame.size.width / 2, y: promptLabelY + 100)
        restartButton.center = CGPoint(x: view.frame.size.width / 2, y: promptLabelY + 100)
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
    
    private func setupRestartButton() {
        view.addSubview(restartButton)
        restartButton.addTarget(self, action: #selector(didTapRestartButton), for: .touchUpInside)
    }
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { [weak self] request, error in
            guard let results = request.results as? [VNFaceObservation], let self = self else { return }
            
            DispatchQueue.main.async {
                self.handleFaceDetectionResults(results)
            }
        })
    }
    
    private func setupPersonSegmentation() {
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }
    
    private func handleFaceDetectionResults(_ results: [VNFaceObservation]) {
        guard let result = results.first else {
            // No face detected
            overlayView.layer.sublayers?.removeAll()
            return
        }
        
        if photoCount == 1, let storedPersonMask = self.storedPersonMask {
            displayStoredMaskDuringCountdown(mask: storedPersonMask)
        } else {
            overlayView.layer.sublayers?.removeAll()
        }
        
        if photoCount == 1, let storedPersonMask = self.storedPersonMask {
            let maskRect = storedPersonMask.extent
            let faceRect = result.boundingBox
            let size = previewLayer.bounds.size
            let origin = CGPoint(x: faceRect.origin.x * size.width,
                                 y: (1 - faceRect.origin.y - faceRect.size.height) * size.height)
            let convertedRect = CGRect(origin: origin,
                                       size: CGSize(width: faceRect.size.width * size.width,
                                                    height: faceRect.size.height * size.height))
            
            if maskRect.contains(convertedRect) {
                startCountdown()
            }
        } else if photoCount == 0 {
            startCountdown()
        }
    }
    
    private func displayStoredMaskDuringCountdown(mask: CIImage) {
        overlayView.layer.sublayers?.removeAll()
        
        let invertedMask = mask.applyingFilter("CIColorInvert")
        let blackMask = invertedMask.applyingFilter("CIMaskToAlpha")
        
        // Rotate 90 degrees counterclockwise and mirror the image
        let rotatedMask = blackMask
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2 * 3))
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        
        // Create a black background image
        let blackBackground = CIImage(color: .black).cropped(to: rotatedMask.extent)
        
        // Blend the mask with the black background
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = blackBackground
        blendFilter.maskImage = rotatedMask
        blendFilter.backgroundImage = CIImage(color: .clear).cropped(to: rotatedMask.extent)
        
        guard let outputImage = blendFilter.outputImage else { return }
        
        let context = CIContext()
        if let cgOutputImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let finalImage = UIImage(cgImage: cgOutputImage)
            
            let maskLayer = CALayer()
            maskLayer.contents = finalImage.cgImage
            maskLayer.frame = overlayView.bounds
            maskLayer.contentsGravity = .resizeAspectFill
            overlayView.layer.addSublayer(maskLayer)
        }
    }
    
    private func startCountdown() {
        guard canTakePhoto else { return }
        canTakePhoto = false
        
        if photoCount == 1, let storedPersonMask = self.storedPersonMask {
            displayStoredMaskDuringCountdown(mask: storedPersonMask)
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
    
    @objc private func didTapRestartButton() {
        resetToStart()
    }
    
    @objc private func didTapTakePhoto() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    private func resetToStart() {
        photoCount = 0
        canTakePhoto = false
        startButton.isHidden = false
        promptLabel.isHidden = true
        overlayView.layer.sublayers?.removeAll()
        storedPersonMask = nil
        storedImage = nil
        restartButton.isHidden = true
        previewLayer.isHidden = false
        session?.startRunning()
    }
    
    private func convertToGrayscale(image: UIImage) -> UIImage? {
        let context = CIContext()
        guard let cgImage = image.cgImage else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        
        if let cgGrayscaleImage = context.createCGImage(grayscale, from: grayscale.extent) {
            return UIImage(cgImage: cgGrayscaleImage)
        }
        return nil
    }
    
    private func getGrayscalePixelValues(image: UIImage) -> [[UInt8]]? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        let bytesPerPixel = 1
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(data: rawData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            rawData.deallocate()
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var pixelValues = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                pixelValues[y][x] = rawData[index]
            }
        }
        
        rawData.deallocate()
        return pixelValues
    }
    
    private func printGrayscalePixelValues(for image: UIImage) {
        if let pixelValues = getGrayscalePixelValues(image: image) {
            for row in pixelValues {
                print(row)
            }
        }
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

        do {
            try handler.perform([segmentationRequest])
            guard let mask = segmentationRequest.results?.first?.pixelBuffer else { return }

            let maskImage = CIImage(cvPixelBuffer: mask)
            let ciImage = CIImage(cgImage: cgImage)

            let maskScaleX = ciImage.extent.width / maskImage.extent.width
            let maskScaleY = ciImage.extent.height / maskImage.extent.height
            let scaledMaskImage = maskImage.transformed(by: .init(scaleX: maskScaleX, y: maskScaleY))

            if photoCount == 0 {
                // Store the mask and image of the first photo
                storedPersonMask = scaledMaskImage
                storedImage = ciImage
            }

            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = ciImage
            blendFilter.maskImage = photoCount == 0 ? scaledMaskImage : storedPersonMask
            blendFilter.backgroundImage = CIImage(color: .white).cropped(to: ciImage.extent)

            guard let outputImage = blendFilter.outputImage else { return }
            let context = CIContext()
            if let cgOutputImage = context.createCGImage(outputImage, from: outputImage.extent) {
                let finalImage = UIImage(cgImage: cgOutputImage)

                // Save the final image
                UIImageWriteToSavedPhotosAlbum(finalImage, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
                
                // Convert to grayscale and save
                if let grayscaleImage = convertToGrayscale(image: finalImage) {
                    UIImageWriteToSavedPhotosAlbum(grayscaleImage, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
                    
                    // Print the dimensions of the grayscale image
                    print("Grayscale image dimensions for photo \(photoCount + 1): \(grayscaleImage.size.width) x \(grayscaleImage.size.height)")

                    // Print grayscale pixel values to the console
                    print("Grayscale pixel values for photo \(photoCount + 1):")
                    printGrayscalePixelValues(for: grayscaleImage)
                }

                photoCount += 1

                if photoCount == 1 {
                    promptLabel.text = "Now make a face and take a second photo"

                    // Display the stored mask during the countdown
                    if let mask = storedPersonMask {
                        displayStoredMaskDuringCountdown(mask: mask)
                    }

                    // Reset the flag to allow another photo after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.canTakePhoto = true
                    }
                } else {
                    promptLabel.text = "Congratulations! You have completed the photo session."
                    restartButton.isHidden = false
                    freezeScreen()
                }
            }
        } catch {
            print("Failed to process image: \(error)")
        }
    }
    
    private func freezeScreen() {
        session?.stopRunning()
        // Leave the preview layer visible to maintain the screen's appearance
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
