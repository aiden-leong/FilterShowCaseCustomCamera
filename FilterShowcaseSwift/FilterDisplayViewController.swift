import UIKit
import GPUImage
import AVFoundation

private var CapturingStillImageContext = 0 //### iOS < 10.0
private var SessionRunningContext = 0
private var FocusModeContext = 0
private var ExposureModeContext = 0
private var WhiteBalanceModeContext = 0
private var LensPositionContext = 0
private var ExposureDurationContext = 0
private var ISOContext = 0
private var ExposureTargetBiasContext = 0
private var ExposureTargetOffsetContext = 0
private var DeviceWhiteBalanceGainsContext = 0
private var LensStabilizationContext = 0 //### iOS < 10.0

let blendImageName = "WID-small.jpg"

class FilterDisplayViewController: UIViewController, UISplitViewControllerDelegate {
    
    @IBOutlet var filterSlider: UISlider?
    @IBOutlet var filterView: RenderView?
    
    @IBOutlet weak var captureModeControl: UISegmentedControl!
    @IBOutlet weak var cameraUnavailableLabel: UILabel!
    @IBOutlet weak var resumeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var photoButton: UIButton!
    @IBOutlet weak var HUDButton: UIButton!
    @IBOutlet weak var manualSegments: UISegmentedControl! //###
    
    @IBOutlet weak var manualHUD: UIView!
    
    private var focusModes: [AVCaptureDevice.FocusMode] = []
    @IBOutlet weak var manualHUDFocusView: UIView!
    @IBOutlet weak var focusModeControl: UISegmentedControl!
    @IBOutlet weak var lensPositionSlider: UISlider!
    @IBOutlet weak var lensPositionNameLabel: UILabel!
    @IBOutlet weak var lensPositionValueLabel: UILabel!
    
    private var exposureModes: [AVCaptureDevice.ExposureMode] = []
    @IBOutlet weak var manualHUDExposureView: UIView!
    @IBOutlet weak var exposureModeControl: UISegmentedControl!
    @IBOutlet weak var exposureDurationSlider: UISlider!
    @IBOutlet weak var exposureDurationNameLabel: UILabel!
    @IBOutlet weak var exposureDurationValueLabel: UILabel!
    @IBOutlet weak var ISOSlider: UISlider!
    @IBOutlet weak var ISONameLabel: UILabel!
    @IBOutlet weak var ISOValueLabel: UILabel!
    @IBOutlet weak var exposureTargetBiasSlider: UISlider!
    @IBOutlet weak var exposureTargetBiasNameLabel: UILabel!
    @IBOutlet weak var exposureTargetBiasValueLabel: UILabel!
    @IBOutlet weak var exposureTargetOffsetSlider: UISlider!
    @IBOutlet weak var exposureTargetOffsetNameLabel: UILabel!
    @IBOutlet weak var exposureTargetOffsetValueLabel: UILabel!
    
    private var whiteBalanceModes: [AVCaptureDevice.WhiteBalanceMode] = []
    @IBOutlet weak var manualHUDWhiteBalanceView: UIView!
    @IBOutlet weak var whiteBalanceModeControl: UISegmentedControl!
    @IBOutlet weak var temperatureSlider: UISlider!
    @IBOutlet weak var temperatureNameLabel: UILabel!
    @IBOutlet weak var temperatureValueLabel: UILabel!
    @IBOutlet weak var tintSlider: UISlider!
    @IBOutlet weak var tintNameLabel: UILabel!
    @IBOutlet weak var tintValueLabel: UILabel!
    
    @IBOutlet weak var manualHUDLensStabilizationView: UIView!
    @IBOutlet weak var lensStabilizationControl: UISegmentedControl!
    
    @IBOutlet weak var manualHUDPhotoView: UIView!
    @IBOutlet weak var rawControl: UISegmentedControl!
    
    // Session management.
    private var sessionQueue: DispatchQueue!
    
    @objc dynamic let videoCamera:Camera?
    var blendImage:PictureInput?
    
    private let kExposureDurationPower = 5.0 // Higher numbers will give the slider more sensitivity at shorter durations
    private let kExposureMinimumDuration = 1.0/1000 // Limit exposure duration to a useful range
    
    
    required init(coder aDecoder: NSCoder)
    {
        do {
            videoCamera = try Camera(sessionPreset: .photo, location:.backFacing)
            videoCamera!.runBenchmark = true
        } catch {
            videoCamera = nil
            print("Couldn't initialize camera with error: \(error)")
        }
        
        do {
            try videoCamera!.inputCamera.lockForConfiguration()
            videoCamera!.inputCamera.activeFormat = videoCamera!.inputCamera.formats[videoCamera!.inputCamera.formats.count - 1]
            
            videoCamera!.inputCamera.setExposureModeCustom(duration: CMTimeMake(1, 2), iso: 100) { (time) in
                
            }
            videoCamera!.inputCamera.exposureMode = .continuousAutoExposure
            videoCamera!.inputCamera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: 6350, tint: -38))
            videoCamera!.inputCamera.whiteBalanceMode = .continuousAutoWhiteBalance
            videoCamera?.inputCamera.focusMode = .continuousAutoFocus
            videoCamera!.inputCamera.unlockForConfiguration()
        } catch {
            
        }
        
        super.init(coder: aDecoder)!
    }
    
    var filterOperation: FilterOperationInterface?
    
    func configureView() {
        guard let videoCamera = videoCamera else {
            let errorAlertController = UIAlertController(title: NSLocalizedString("Error", comment: "Error"), message: "Couldn't initialize camera", preferredStyle: .alert)
            errorAlertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK"), style: .default, handler: nil))
            self.present(errorAlertController, animated: true, completion: nil)
            return
        }
        if let currentFilterConfiguration = self.filterOperation {
            self.title = currentFilterConfiguration.titleName
            
            // Configure the filter chain, ending with the view
            if let view = self.filterView {
                switch currentFilterConfiguration.filterOperationType {
                case .singleInput:
                    videoCamera.addTarget(currentFilterConfiguration.filter)
                    currentFilterConfiguration.filter.addTarget(view)
                case .blend:
                    videoCamera.addTarget(currentFilterConfiguration.filter)
                    self.blendImage = PictureInput(imageName:blendImageName)
                    self.blendImage?.addTarget(currentFilterConfiguration.filter)
                    self.blendImage?.processImage()
                    currentFilterConfiguration.filter.addTarget(view)
                case let .custom(filterSetupFunction:setupFunction):
                    currentFilterConfiguration.configureCustomFilter(setupFunction(videoCamera, currentFilterConfiguration.filter, view))
                }
                
                videoCamera.startCapture()
            }
            
            // Hide or display the slider, based on whether the filter needs it
            if let slider = self.filterSlider {
                switch currentFilterConfiguration.sliderConfiguration {
                case .disabled:
                    slider.isHidden = true
                //                case let .Enabled(minimumValue, initialValue, maximumValue, filterSliderCallback):
                case let .enabled(minimumValue, maximumValue, initialValue):
                    slider.minimumValue = minimumValue
                    slider.maximumValue = maximumValue
                    slider.value = initialValue
                    slider.isHidden = false
                    self.updateSliderValue()
                }
            }
            
        }
    }
    
    @IBAction func updateSliderValue() {
        if let currentFilterConfiguration = self.filterOperation {
            switch (currentFilterConfiguration.sliderConfiguration) {
            case .enabled(_, _, _): currentFilterConfiguration.updateBasedOnSliderValue(Float(self.filterSlider!.value))
            case .disabled: break
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.configureView()
        DispatchQueue.main.async {
            self.configureManualHUD()
        }
//
//        self.captureModeControl.isEnabled = false
//        self.HUDButton.isEnabled = false
//
//        self.manualHUD.isHidden = true
//        self.manualHUDPhotoView.isHidden = true
//        self.manualHUDFocusView.isHidden = true
//        self.manualHUDExposureView.isHidden = true
//        self.manualHUDWhiteBalanceView.isHidden = true
//        self.manualHUDLensStabilizationView.isHidden = true

    }
    
    override func viewWillAppear(_ animated: Bool) {
         self.addObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if let videoCamera = videoCamera {
            videoCamera.stopCapture()
            for input in videoCamera.captureSession.inputs {
                videoCamera.captureSession.removeInput(input)
            }
            videoCamera.removeAllTargets()
            blendImage?.removeAllTargets()
            
            removeObservers()
        }
        
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: HUD
    
    private func configureManualHUD() {
        // Manual focus controls
        self.focusModes = [.continuousAutoFocus, .locked]
        
        self.focusModeControl.isEnabled = (self.videoCamera!.inputCamera != nil)
        if let videoDevice = self.videoCamera!.inputCamera {//###
            self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: videoDevice.focusMode)!
            for mode in self.focusModes {
                self.focusModeControl.setEnabled(videoDevice.isFocusModeSupported(mode), forSegmentAt: self.focusModes.index(of: mode)!)
            }
        }
        
        self.lensPositionSlider.minimumValue = 0.0
        self.lensPositionSlider.maximumValue = 1.0
        self.lensPositionSlider.value = self.videoCamera!.inputCamera?.lensPosition ?? 0
        self.lensPositionSlider.isEnabled = (self.videoCamera!.inputCamera != nil && self.videoCamera!.inputCamera!.isFocusModeSupported(.locked) && self.videoCamera!.inputCamera!.focusMode == .locked)
        
        // Manual exposure controls
        self.exposureModes = [.continuousAutoExposure, .locked, .custom]
        
        
        self.exposureModeControl.isEnabled = (self.videoCamera!.inputCamera != nil)
        if let videoDevice = self.videoCamera!.inputCamera {
            self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: videoDevice.exposureMode)!
            for mode in self.exposureModes {
                self.exposureModeControl.setEnabled(videoDevice.isExposureModeSupported(mode), forSegmentAt: self.exposureModes.index(of: mode)!)
            }
        }
        
        // Use 0-1 as the slider range and do a non-linear mapping from the slider value to the actual device exposure duration
        self.exposureDurationSlider.minimumValue = 0
        self.exposureDurationSlider.maximumValue = 1
        let exposureDurationSeconds = CMTimeGetSeconds(self.videoCamera!.inputCamera?.exposureDuration ?? CMTime())
        let minExposureDurationSeconds = max(CMTimeGetSeconds(self.videoCamera!.inputCamera?.activeFormat.minExposureDuration ?? CMTime()), kExposureMinimumDuration)
        let maxExposureDurationSeconds = CMTimeGetSeconds(self.videoCamera!.inputCamera?.activeFormat.maxExposureDuration ?? CMTime())
        // Map from duration to non-linear UI range 0-1
        let p = (exposureDurationSeconds - minExposureDurationSeconds) / (maxExposureDurationSeconds - minExposureDurationSeconds) // Scale to 0-1
        self.exposureDurationSlider.value = Float(pow(p, 1 / kExposureDurationPower)) // Apply inverse power
        self.exposureDurationSlider.isEnabled = (self.videoCamera!.inputCamera != nil && self.videoCamera!.inputCamera!.exposureMode == .custom)
        
        self.ISOSlider.minimumValue = self.videoCamera!.inputCamera?.activeFormat.minISO ?? 0.0
        self.ISOSlider.maximumValue = self.videoCamera!.inputCamera?.activeFormat.maxISO ?? 0.0
        self.ISOSlider.value = self.videoCamera!.inputCamera?.iso ?? 0.0
        self.ISOSlider.isEnabled = (self.videoCamera!.inputCamera?.exposureMode == .custom)
        
        self.exposureTargetBiasSlider.minimumValue = self.videoCamera!.inputCamera?.minExposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.maximumValue = self.videoCamera!.inputCamera?.maxExposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.value = self.videoCamera!.inputCamera?.exposureTargetBias ?? 0.0
        self.exposureTargetBiasSlider.isEnabled = (self.videoCamera!.inputCamera != nil)
        
        self.exposureTargetOffsetSlider.minimumValue = self.videoCamera!.inputCamera?.minExposureTargetBias ?? 0.0
        self.exposureTargetOffsetSlider.maximumValue = self.videoCamera!.inputCamera?.maxExposureTargetBias ?? 0.0
        self.exposureTargetOffsetSlider.value = self.videoCamera!.inputCamera?.exposureTargetOffset ?? 0.0
        self.exposureTargetOffsetSlider.isEnabled = false
        
        // Manual white balance controls
        self.whiteBalanceModes = [.continuousAutoWhiteBalance, .locked]
        
        self.whiteBalanceModeControl.isEnabled = (self.videoCamera!.inputCamera != nil)
        if let videoDevice = self.videoCamera!.inputCamera {
            self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: videoDevice.whiteBalanceMode)!
            for mode in self.whiteBalanceModes {
                self.whiteBalanceModeControl.setEnabled(videoDevice.isWhiteBalanceModeSupported(mode), forSegmentAt: self.whiteBalanceModes.index(of: mode)!)
            }
        }
        
        let whiteBalanceGains = self.videoCamera!.inputCamera?.deviceWhiteBalanceGains ?? AVCaptureDevice.WhiteBalanceGains()
        let whiteBalanceTemperatureAndTint = self.videoCamera!.inputCamera?.temperatureAndTintValues(for: whiteBalanceGains) ?? AVCaptureDevice.WhiteBalanceTemperatureAndTintValues()
        
        self.temperatureSlider.minimumValue = 3000
        self.temperatureSlider.maximumValue = 8000
        self.temperatureSlider.value = whiteBalanceTemperatureAndTint.temperature
        self.temperatureSlider.isEnabled = (self.videoCamera!.inputCamera?.whiteBalanceMode == .locked)
        
        self.tintSlider.minimumValue = -150
        self.tintSlider.maximumValue = 150
        self.tintSlider.value = whiteBalanceTemperatureAndTint.tint
        self.tintSlider.isEnabled = (self.videoCamera!.inputCamera?.whiteBalanceMode == .locked)
        
//        if #available(iOS 10.0, *) {
//            self.lensStabilizationControl.isEnabled = (self.videoDevice != nil)
//            self.lensStabilizationControl.selectedSegmentIndex = 0
//            self.lensStabilizationControl.setEnabled(self.photoOutput!.isLensStabilizationDuringBracketedCaptureSupported, forSegmentAt: 1)
//        } else if #available(iOS 9.0, *) {
//            self.lensStabilizationControl.isEnabled = (self.videoDevice != nil)
//            self.lensStabilizationControl.selectedSegmentIndex = (self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureEnabled ? 1 : 0)
//            self.lensStabilizationControl.setEnabled(self.stillImageOutput!.isLensStabilizationDuringBracketedCaptureSupported, forSegmentAt: 1)
//        } else {
//            self.manualSegments.setEnabled(false, forSegmentAt: 4)
//            self.lensStabilizationControl.isHidden = true
//        }
        
        self.rawControl.isEnabled = (self.videoCamera!.inputCamera != nil)
        self.rawControl.selectedSegmentIndex = 0
    }
    
    @IBAction func toggleHUD(_ sender: Any) {
        self.manualHUD.isHidden = !self.manualHUD.isHidden
    }
    
    @IBAction func changeManualHUD(_ control: UISegmentedControl) {
        
        self.manualHUDPhotoView.isHidden = (control.selectedSegmentIndex != 0)
        self.manualHUDFocusView.isHidden = (control.selectedSegmentIndex != 1)
        self.manualHUDExposureView.isHidden = (control.selectedSegmentIndex != 2)
        self.manualHUDWhiteBalanceView.isHidden = (control.selectedSegmentIndex != 3)
        if #available(iOS 9.0, *) {
            self.manualHUDLensStabilizationView.isHidden = (control.selectedSegmentIndex != 4)
        } else {
            self.manualHUDLensStabilizationView.isHidden = true
        }
    }
    
    private func set(_ slider: UISlider, highlight color: UIColor) {
        slider.tintColor = color
        
        if slider === self.lensPositionSlider {
            self.lensPositionNameLabel.textColor = slider.tintColor
            self.lensPositionValueLabel.textColor = slider.tintColor
        } else if slider === self.exposureDurationSlider {
            self.exposureDurationNameLabel.textColor = slider.tintColor
            self.exposureDurationValueLabel.textColor = slider.tintColor
        } else if slider === self.ISOSlider {
            self.ISONameLabel.textColor = slider.tintColor
            self.ISOValueLabel.textColor = slider.tintColor
        } else if slider === self.exposureTargetBiasSlider {
            self.exposureTargetBiasNameLabel.textColor = slider.tintColor
            self.exposureTargetBiasValueLabel.textColor = slider.tintColor
        } else if slider === self.temperatureSlider {
            self.temperatureNameLabel.textColor = slider.tintColor
            self.temperatureValueLabel.textColor = slider.tintColor
        } else if slider === self.tintSlider {
            self.tintNameLabel.textColor = slider.tintColor
            self.tintValueLabel.textColor = slider.tintColor
        }
    }
    
    @IBAction func sliderTouchBegan(_ slider: UISlider) {
        self.set(slider, highlight: UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0))
    }
    
    @IBAction func sliderTouchEnded(_ slider: UISlider) {
        self.set(slider, highlight: UIColor.yellow)
    }
    
    @IBAction func resumeInterruptedSession(_: AnyObject) {
        
    }
    
    @IBAction func changeCaptureMode(_ captureModeControl: UISegmentedControl) {
        
    }
    
    
    @IBAction func changeFocusMode(_ control: UISegmentedControl) {
        let mode = self.focusModes[control.selectedSegmentIndex]
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            if self.videoCamera!.inputCamera!.isFocusModeSupported(mode) {
                self.videoCamera!.inputCamera!.focusMode = mode
            } else {
                NSLog("Focus mode %@ is not supported. Focus mode is %@.", mode.description, self.videoCamera!.inputCamera!.focusMode.description)
                self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: self.videoCamera!.inputCamera!.focusMode)!
            }
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeLensPosition(_ control: UISlider) {
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            self.videoCamera!.inputCamera!.setFocusModeLocked(lensPosition: control.value, completionHandler: nil)
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func focusWithMode(_ focusMode: AVCaptureDevice.FocusMode, exposeWithMode exposureMode: AVCaptureDevice.ExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        guard let device = self.videoCamera!.inputCamera else {
            print("videoDevice unavailable")
            return
        }
        self.sessionQueue.async {
            
            do {
                try device.lockForConfiguration()
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                if focusMode != .locked && device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                
                if exposureMode != .custom && device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    
    @IBAction func changeExposureMode(_ control: UISegmentedControl) {
        let mode = self.exposureModes[control.selectedSegmentIndex]
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            if (self.videoCamera!.inputCamera!.isExposureModeSupported(mode)) {
                self.videoCamera!.inputCamera!.exposureMode = mode
            } else {
                NSLog("Exposure mode %@ is not supported. Exposure mode is %@.", mode.description, self.videoCamera!.inputCamera!.exposureMode.description)
                self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: self.videoCamera!.inputCamera!.exposureMode)!
            }
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeExposureDuration(_ control: UISlider) {
        
        let p = pow(Double(control.value), kExposureDurationPower) // Apply power function to expand slider's low-end range
        let minDurationSeconds = max(CMTimeGetSeconds(self.videoCamera!.inputCamera!.activeFormat.minExposureDuration), kExposureMinimumDuration)
        let maxDurationSeconds = CMTimeGetSeconds(self.videoCamera!.inputCamera!.activeFormat.maxExposureDuration)
        let newDurationSeconds = p * ( maxDurationSeconds - minDurationSeconds ) + minDurationSeconds; // Scale from 0-1 slider range to actual duration
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            self.videoCamera!.inputCamera!.setExposureModeCustom(duration: CMTimeMakeWithSeconds(newDurationSeconds, 1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: nil)
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeISO(_ control: UISlider) {
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            self.videoCamera!.inputCamera!.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: control.value, completionHandler: nil)
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeExposureTargetBias(_ control: UISlider) {
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            self.videoCamera!.inputCamera!.setExposureTargetBias(control.value, completionHandler: nil)
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeWhiteBalanceMode(_ control: UISegmentedControl) {
        let mode = self.whiteBalanceModes[control.selectedSegmentIndex]
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            if self.videoCamera!.inputCamera!.isWhiteBalanceModeSupported(mode) {
                self.videoCamera!.inputCamera!.whiteBalanceMode = mode
            } else {
                NSLog("White balance mode %@ is not supported. White balance mode is %@.", mode.description, self.videoCamera!.inputCamera!.whiteBalanceMode.description)
                self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: self.videoCamera!.inputCamera!.whiteBalanceMode)!
            }
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func setWhiteBalanceGains(_ gains: AVCaptureDevice.WhiteBalanceGains) {
        
        do {
            try self.videoCamera!.inputCamera!.lockForConfiguration()
            let normalizedGains = self.normalizedGains(gains) // Conversion can yield out-of-bound values, cap to limits
            self.videoCamera!.inputCamera!.setWhiteBalanceModeLocked(with: normalizedGains, completionHandler: nil)
            self.videoCamera!.inputCamera!.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    @IBAction func changeTemperature(_: AnyObject) {
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoCamera!.inputCamera!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func changeTint(_: AnyObject) {
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: self.temperatureSlider.value,
            tint: self.tintSlider.value
        )
        
        self.setWhiteBalanceGains(self.videoCamera!.inputCamera!.deviceWhiteBalanceGains(for: temperatureAndTint))
    }
    
    @IBAction func lockWithGrayWorld(_: AnyObject) {
        self.setWhiteBalanceGains(self.videoCamera!.inputCamera!.grayWorldDeviceWhiteBalanceGains)
    }
    
    private func normalizedGains(_ gains: AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        
        g.redGain = max(1.0, g.redGain)
        g.greenGain = max(1.0, g.greenGain)
        g.blueGain = max(1.0, g.blueGain)
        
        g.redGain = min(self.videoCamera!.inputCamera!.maxWhiteBalanceGain, g.redGain)
        g.greenGain = min(self.videoCamera!.inputCamera!.maxWhiteBalanceGain, g.greenGain)
        g.blueGain = min(self.videoCamera!.inputCamera!.maxWhiteBalanceGain, g.blueGain)
        
        return g
    }
    
    //MARK: Capturing Photos
    
    @IBAction func capturePhoto(_: Any) {
        if #available(iOS 10.0, *) {
            self.capturePhoto()
        } else {
            //self.snapStillImage()
        }
    }
    @available(iOS 10.0, *)
    private func capturePhoto() {
        // Retrieve the video preview layer's video orientation on the main queue before entering the session queue
        // We do this to ensure UI elements are accessed on the main thread and session configuration is done on the session queue
        
        
    }
    
    
    //MARK: KVO and Notifications
    
    private func addObservers() {
//        self.addObserver(self, forKeyPath: "session.running", options: .new, context: &SessionRunningContext)
        
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.focusMode", options: [.old, .new], context: &FocusModeContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.lensPosition", options: .new, context: &LensPositionContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.exposureMode", options: [.old, .new], context: &ExposureModeContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.exposureDuration", options: .new, context: &ExposureDurationContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.ISO", options: .new, context: &ISOContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.exposureTargetBias", options: .new, context: &ExposureTargetBiasContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.exposureTargetOffset", options: .new, context: &ExposureTargetOffsetContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.whiteBalanceMode", options: [.old, .new], context: &WhiteBalanceModeContext)
        self.addObserver(self, forKeyPath: "videoCamera.inputCamera.deviceWhiteBalanceGains", options: .new, context: &DeviceWhiteBalanceGainsContext)
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: self.videoCamera!.inputCamera!)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        if #available(iOS 9.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: self.videoCamera?.captureSession)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: self.videoCamera?.captureSession)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
//        self.removeObserver(self, forKeyPath: "session.running", context: &SessionRunningContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.focusMode", context: &FocusModeContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.lensPosition", context: &LensPositionContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.exposureMode", context: &ExposureModeContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.exposureDuration", context: &ExposureDurationContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.ISO", context: &ISOContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.exposureTargetBias", context: &ExposureTargetBiasContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.exposureTargetOffset", context: &ExposureTargetOffsetContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.whiteBalanceMode", context: &WhiteBalanceModeContext)
        self.removeObserver(self, forKeyPath: "videoCamera.inputCamera.deviceWhiteBalanceGains", context: &DeviceWhiteBalanceGainsContext)
        
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let oldValue = change![.oldKey]
        let newValue = change![.newKey]
        
        guard let context = context else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: nil)
            return
        }
        switch context {
        case &FocusModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.FocusMode(rawValue: value)!
                DispatchQueue.main.async {
                    self.focusModeControl.selectedSegmentIndex = self.focusModes.index(of: newMode)!
                    self.lensPositionSlider.isEnabled = (newMode == .locked)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.FocusMode(rawValue: old)!
                        NSLog("focus mode: \(oldMode) -> \(newMode)")
                    } else {
                        NSLog("focus mode: \(newMode)")
                    }
                }
            }
        case &LensPositionContext:
            if let value = newValue as? Float {
                let focusMode = self.videoCamera!.inputCamera!.focusMode
                let newLensPosition = value
                
                DispatchQueue.main.async {
                    if focusMode != .locked {
                        self.lensPositionSlider.value = newLensPosition
                    }
                    
                    self.lensPositionValueLabel.text = String(format: "%.2f", Double(newLensPosition))
                }
            }
        case &ExposureModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.ExposureMode(rawValue: value)!
                if let old = oldValue as? Int {
                    let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                    /*
                     It’s important to understand the relationship between exposureDuration and the minimum frame rate as represented by activeVideoMaxFrameDuration.
                     In manual mode, if exposureDuration is set to a value that's greater than activeVideoMaxFrameDuration, then activeVideoMaxFrameDuration will
                     increase to match it, thus lowering the minimum frame rate. If exposureMode is then changed to automatic mode, the minimum frame rate will
                     remain lower than its default. If this is not the desired behavior, the min and max frameRates can be reset to their default values for the
                     current activeFormat by setting activeVideoMaxFrameDuration and activeVideoMinFrameDuration to kCMTimeInvalid.
                     */
                    if oldMode != newMode && oldMode == .custom {
                        do {
                            try self.videoCamera!.inputCamera!.lockForConfiguration()
                            defer {self.videoCamera!.inputCamera!.unlockForConfiguration()}
                            self.videoCamera!.inputCamera!.activeVideoMaxFrameDuration = kCMTimeInvalid
                            self.videoCamera!.inputCamera!.activeVideoMinFrameDuration = kCMTimeInvalid
                        } catch let error {
                            NSLog("Could not lock device for configuration: \(error)")
                        }
                    }
                }
                DispatchQueue.main.async {
                    
                    self.exposureModeControl.selectedSegmentIndex = self.exposureModes.index(of: newMode)!
                    self.exposureDurationSlider.isEnabled = (newMode == .custom)
                    self.ISOSlider.isEnabled = (newMode == .custom)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.ExposureMode(rawValue: old)!
                        NSLog("exposure mode: \(oldMode) -> \(newMode)")
                    } else {
                        NSLog("exposure mode: \(newMode)")
                    }
                }
            }
        case &ExposureDurationContext:
            // Map from duration to non-linear UI range 0-1
            
            if let value = newValue as? CMTime {
                let newDurationSeconds = CMTimeGetSeconds(value)
                let exposureMode = self.videoCamera!.inputCamera!.exposureMode
                
                let minDurationSeconds = max(CMTimeGetSeconds(self.videoCamera!.inputCamera!.activeFormat.minExposureDuration), kExposureMinimumDuration)
                let maxDurationSeconds = CMTimeGetSeconds(self.videoCamera!.inputCamera!.activeFormat.maxExposureDuration)
                // Map from duration to non-linear UI range 0-1
                let p = (newDurationSeconds - minDurationSeconds) / (maxDurationSeconds - minDurationSeconds) // Scale to 0-1
                DispatchQueue.main.async {
                    if exposureMode != .custom {
                        self.exposureDurationSlider.value = Float(pow(p, 1 / self.kExposureDurationPower)) // Apply inverse power
                    }
                    if newDurationSeconds < 1 {
                        let digits = max(0, 2 + Int(floor(log10(newDurationSeconds))))
                        self.exposureDurationValueLabel.text = String(format: "1/%.*f", digits, 1/newDurationSeconds)
                    } else {
                        self.exposureDurationValueLabel.text = String(format: "%.2f", newDurationSeconds)
                    }
                }
            }
        case &ISOContext:
            if let value = newValue as? Float {
                let newISO = value
                let exposureMode = self.videoCamera!.inputCamera!.exposureMode
                
                DispatchQueue.main.async {
                    if exposureMode != .custom {
                        self.ISOSlider.value = newISO
                    }
                    self.ISOValueLabel.text = String(Int(newISO))
                }
            }
        case &ExposureTargetBiasContext:
            if let value = newValue as? Float {
                let newExposureTargetBias = value
                DispatchQueue.main.async {
                    self.exposureTargetBiasValueLabel.text = String(format: "%.1f", Double(newExposureTargetBias))
                }
            }
        case &ExposureTargetOffsetContext:
            if let value = newValue as? Float {
                let newExposureTargetOffset = value
                DispatchQueue.main.async {
                    self.exposureTargetOffsetSlider.value = newExposureTargetOffset
                    self.exposureTargetOffsetValueLabel.text = String(format: "%.1f", Double(newExposureTargetOffset))
                }
            }
        case &WhiteBalanceModeContext:
            if let value = newValue as? Int {
                let newMode = AVCaptureDevice.WhiteBalanceMode(rawValue: value)!
                DispatchQueue.main.async {
                    self.whiteBalanceModeControl.selectedSegmentIndex = self.whiteBalanceModes.index(of: newMode)!
                    self.temperatureSlider.isEnabled = (newMode == .locked)
                    self.tintSlider.isEnabled = (newMode == .locked)
                    
                    if let old = oldValue as? Int {
                        let oldMode = AVCaptureDevice.WhiteBalanceMode(rawValue: old)!
                        NSLog("white balance mode: \(oldMode) -> \(newMode)")
                    }
                }
            }
        case &DeviceWhiteBalanceGainsContext:
            if let value = newValue as? NSValue {
                var newGains = AVCaptureDevice.WhiteBalanceGains()
                value.getValue(&newGains)
                
                let newTemperatureAndTint = self.videoCamera!.inputCamera!.temperatureAndTintValues(for: newGains)
                let whiteBalanceMode = self.videoCamera!.inputCamera!.whiteBalanceMode
                DispatchQueue.main.async {
                    if whiteBalanceMode != .locked {
                        self.temperatureSlider.value = newTemperatureAndTint.temperature
                        self.tintSlider.value = newTemperatureAndTint.tint
                    }
                    
                    self.temperatureValueLabel.text = String(Int(newTemperatureAndTint.temperature))
                    self.tintValueLabel.text = String(Int(newTemperatureAndTint.tint))
                }
            }
        case &SessionRunningContext:
            var isRunning = false
            if let value = newValue as? Bool {
                isRunning = value
            }
            
            DispatchQueue.main.async {
                //                if #available(iOS 10.0, *) {
                //                    self.cameraButton.isEnabled = isRunning && (self.videoCamera!.inputCameraDiscoverySession?.devices.count ?? 0 > 1)
                //                } else {
                //                    self.cameraButton.isEnabled = (isRunning && AVCaptureDevice.devices(for: AVMediaType.video).count > 1)
                //                }
                //                self.recordButton.isEnabled = isRunning && (self.captureModeControl.selectedSegmentIndex == AVCamManualCaptureMode.movie.rawValue)
                self.photoButton.isEnabled = isRunning
                self.HUDButton.isEnabled = isRunning
                self.captureModeControl.isEnabled = isRunning
            }
        case &CapturingStillImageContext:
            if #available(iOS 10.0, *) {
            } else {
                var isCapturingStillImage = false
                if let value = newValue as? Bool {
                    isCapturingStillImage = value
                }
                
                if isCapturingStillImage {
                    //                    DispatchQueue.main.async {
                    //                        self.previewView.layer.opacity = 0.0
                    //                        UIView.animate(withDuration: 0.25, animations: {
                    //                            self.previewView.layer.opacity = 1.0
                    //                        })
                    //                    }
                }
            }
        case &LensStabilizationContext:
            if #available(iOS 10.0, *) {
            } else {
                if let value = newValue as? Bool {
                    let newMode = value
                    self.lensStabilizationControl.selectedSegmentIndex = (newMode ? 1 : 0)
                    if let old = oldValue as? Bool {
                        let oldMode = old
                        NSLog("Lens stabilization: %@ -> %@", (oldMode ? "YES" : "NO"), (newMode ? "YES" : "NO"))
                    }
                }
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func subjectAreaDidChange(_ notificaiton: Notification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(.continuousAutoFocus, exposeWithMode: .continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: false)
    }
    
    
    @objc @available(iOS 9.0, *)
    func sessionWasInterrupted(_ notification: Notification) {
        // In some scenarios we want to enable the user to restart the capture session.
        // For example, if music playback is initiated via Control Center while using AVCamManual,
        // then the user can let AVCamManual resume the session running, which will stop music playback.
        // Note that stopping music playback in Control Center will not automatically resume the session.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        // In iOS 9 and later, the notification's userInfo dictionary contains information about why the session was interrupted
        let reason = AVCaptureSession.InterruptionReason(rawValue: notification.userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int)!
        NSLog("Capture session was interrupted with reason %ld", reason.rawValue)
        
        if reason == .audioDeviceInUseByAnotherClient ||
            reason == .videoDeviceInUseByAnotherClient {
            // Simply fade-in a button to enable the user to try to resume the session running.
            self.resumeButton.isHidden = false
            self.resumeButton.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 1.0
            })
        } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            self.cameraUnavailableLabel.isHidden = false
            self.cameraUnavailableLabel.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 1.0
            })
        }
    }
    
    @objc func sessionInterruptionEnded(_ notification: Notification) {
        NSLog("Capture session interruption ended")
        
        if !self.resumeButton.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.resumeButton.alpha = 0.0
            }, completion: {finished in
                self.resumeButton.isHidden = true
            })
        }
        if !self.cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.cameraUnavailableLabel.alpha = 0.0
            }, completion: {finished in
                self.cameraUnavailableLabel.isHidden = true
            })
        }
    }
    
    
    
    @available(iOS, deprecated: 10.0)
    private class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devices(for: AVMediaType(rawValue: mediaType))
        var captureDevice = devices.first
        
        for device in devices {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    
    
    @available(iOS, deprecated: 10.0)
    class func setFlashMode(_ flashMode: AVCaptureDevice.FlashMode, forDevice device: AVCaptureDevice) {
        if device.hasFlash && device.isFlashModeSupported(flashMode) {
            do {
                try device.lockForConfiguration()
                device.flashMode = flashMode
                device.unlockForConfiguration()
            } catch let error {
                NSLog("Could not lock device for configuration: \(error)")
            }
        }
    }
}

extension AVCaptureDevice.FocusMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
        case .locked:
            string = "Locked"
        case .autoFocus:
            string = "Auto"
        case .continuousAutoFocus:
            string = "ContinuousAuto"
        }
        
        return string
    }
}

extension AVCaptureDevice.ExposureMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
        case .locked:
            string = "Locked"
        case .autoExpose:
            string = "Auto"
        case .continuousAutoExposure:
            string = "ContinuousAuto"
        case .custom:
            string = "Custom"
        }
        
        return string
    }
}

extension AVCaptureDevice.WhiteBalanceMode: CustomStringConvertible {
    public var description: String {
        var string: String
        
        switch self {
        case .locked:
            string = "Locked"
        case .autoWhiteBalance:
            string = "Auto"
        case .continuousAutoWhiteBalance:
            string = "ContinuousAuto"
        }
        
        return string
    }
}

