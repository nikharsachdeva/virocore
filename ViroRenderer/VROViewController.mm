//
//  VROViewController.m
//  ViroRenderer
//
//  Created by Raj Advani on 10/23/15.
//  Copyright © 2015 Viro Media. All rights reserved.
//

#import "VROViewController.h"

#import "VRODevice.h"
#import "VRODistortion.h"
#import "VRODistortionRenderer.h"
#import "VROEye.h"
#import "VROFieldOfView.h"
#import "VROViewport.h"
#import "VROHeadMountedDisplay.h"
#import "VROHeadTransform.h"
#import "VROScreen.h"
#import "VROHeadTransform.h"
#import "VROHeadTracker.h"
#import "VROMagnetSensor.h"
#import "VRORenderContextMetal.h"
#import "VROAnimation.h"

@interface VROEyePerspective ()

@property (nonatomic) VROEye *eye;

- (instancetype)initWithEye:(VROEye *)eye;

@end


@implementation VROEyePerspective

- (instancetype)init {
    return [self initWithEye:nullptr];
}

- (instancetype)initWithEye:(VROEye *)eye {
    self = [super init];
    if (self) {
        _eye = eye;
    }
    
    return self;
}

- (VROEyeType)type {
    VROEyeType type = VROEyeTypeMonocular;
    if (_eye->getType() == VROEye::TypeLeft) {
        type = VROEyeTypeLeft;
    }
    else if (_eye->getType() == VROEye::TypeRight) {
        type = VROEyeTypeRight;
    }
    
    return type;
}

- (matrix_float4x4)eyeViewMatrix {
    if (_eye != nullptr) {
        return _eye->getEyeView();
    }
    else {
        return matrix_identity_float4x4;
    }
}

- (matrix_float4x4)perspectiveMatrixWithZNear:(float)zNear
                                         zFar:(float)zFar {
    if (_eye != nullptr) {
        return _eye->perspective(zNear, zFar);
    }
    else {
        return matrix_identity_float4x4;
    }
}

@end

@interface VROViewController () {
    VROMagnetSensor *_magnetSensor;
    VROHeadTracker *_headTracker;
    VROHeadTransform *_headTransform;
    VROHeadMountedDisplay *_headMountedDisplay;
    
    VROEye *_monocularEye;
    VROEye *_leftEye;
    VROEye *_rightEye;
    
    VRODistortionRenderer *_distortionRenderer;
    
    VRORenderContextMetal *_renderContext;
    dispatch_semaphore_t _inflight_semaphore;
    
    float _distortionCorrectionScale;
    
    float _zNear;
    float _zFar;
    
    BOOL _projectionChanged;
    
    BOOL _frameParamentersReady;
}

@property (nonatomic) NSRecursiveLock *glLock;

@property (nonatomic) VROEyePerspective *leftEyeWrapper;
@property (nonatomic) VROEyePerspective *rightEyeWrapper;

@end

@implementation VROViewController

@dynamic view;

- (void)awakeFromNib {
    // Do not allow the display to go into sleep
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _magnetSensor = new VROMagnetSensor();
    _headTracker = new VROHeadTracker();
    _headTransform = new VROHeadTransform();
    _headMountedDisplay = new VROHeadMountedDisplay([UIScreen mainScreen]);
    
    _monocularEye = new VROEye(VROEye::TypeMonocular);
    _leftEye = new VROEye(VROEye::TypeLeft);
    _rightEye = new VROEye(VROEye::TypeRight);
    
    _distortionRenderer = new VRODistortionRenderer();
    
    _distortionCorrectionScale = 1.0f;
    
    _vrModeEnabled = YES;
    _distortionCorrectionEnabled = YES;
    
    _zNear = 0.1f;
    _zFar = 100.0f;
    
    _projectionChanged = YES;
    
    _frameParamentersReady = NO;
    
    self.leftEyeWrapper = [VROEyePerspective new];
    self.rightEyeWrapper = [VROEyePerspective new];
    
    _headTracker->startTracking([UIApplication sharedApplication].statusBarOrientation);
    _magnetSensor->start();
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(magneticTriggerPressed:)
                                                 name:VROTriggerPressedNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationDidChange:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
}

- (void)orientationDidChange:(NSNotification *)notification {
    _headTracker->updateDeviceOrientation([UIApplication sharedApplication].statusBarOrientation);
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    id <MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    MTKView *view = (MTKView *)self.view;
    view.device = device;
    view.delegate = self;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
    _inflight_semaphore = dispatch_semaphore_create(3);
    
#pragma warning Delete this
    _renderContext = new VRORenderContextMetal(view, device);
    
    [self.stereoRendererDelegate setupRendererWithView:self.view context:_renderContext];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stereoRendererDelegate shutdownRendererWithView:self.view];
    
    if (_magnetSensor != nullptr) {
        delete (_magnetSensor);
    }
    if (_headTracker != nullptr) {
        delete (_headTracker);
    }
    if (_headTransform != nullptr) {
        delete (_headTransform);
    }
    if (_headMountedDisplay != nullptr) {
        delete (_headMountedDisplay);
    }
    
    if (_monocularEye != nullptr) {
        delete (_monocularEye);
    }
    if (_leftEye != nullptr) {
        delete (_leftEye);
    }
    if (_rightEye != nullptr) {
        delete (_rightEye);
    }
    
    if (_distortionRenderer != nullptr) {
        delete (_distortionRenderer);
    }
}

- (BOOL)vignetteEnabled {
    return _distortionRenderer->isVignetteEnabled();
}

- (void)setVignetteEnabled:(BOOL)vignetteEnabled {
    _distortionRenderer->setVignetteEnabled(vignetteEnabled);
}

- (BOOL)chromaticAberrationCorrectionEnabled {
    return _distortionRenderer->isChromaticAberrationEnabled();
}

- (void)setChromaticAberrationCorrectionEnabled:(BOOL)chromaticAberrationCorrectionEnabled {
    _distortionRenderer->setChromaticAberrationEnabled(chromaticAberrationCorrectionEnabled);
}

- (BOOL)neckModelEnabled {
    return _headTracker->isNeckModelEnabled();
}

- (void)setNeckModelEnabled:(BOOL)neckModelEnabled {
    _headTracker->setNeckModelEnabled(neckModelEnabled);
}

- (void)magneticTriggerPressed:(NSNotification *)notification {
    if ([self.stereoRendererDelegate respondsToSelector:@selector(magneticTriggerPressed)]) {
        [self.stereoRendererDelegate magneticTriggerPressed];
    }
}

- (void)glkViewController:(GLKViewController *)controller willPause:(BOOL)pause {
    if (pause) {
        _headTracker->stopTracking();
        _magnetSensor->stop();
    }
    else {
        _headTracker->startTracking([UIApplication sharedApplication].statusBarOrientation);
        _magnetSensor->start();
    }
}

// Called whenever view changes orientation or layout is changed
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    //[self _reshape];
}

// Called whenever the view needs to render
- (void)drawInMTKView:(nonnull MTKView *)view {
    if (!_headTracker->isReady()) {
        return;
    }
    
    dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
    
    @autoreleasepool {
        [self calculateFrameParametersWithHeadTransform:_headTransform
                                                leftEye:_leftEye
                                               rightEye:_rightEye
                                           monocularEye:_monocularEye];
        _frameParamentersReady = YES;
        
        /*
         A single command buffer collects all render events for frame.
         */
        id <MTLCommandBuffer> commandBuffer = [_renderContext->getCommandQueue() commandBuffer];
        commandBuffer.label = @"CommandBuffer";
        
        /*
         When the command buffer is executed by the GPU, signal the semaphor
         (required by the view since it will signal set up the next buffer).
         */
        __block dispatch_semaphore_t block_sema = _inflight_semaphore;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
            dispatch_semaphore_signal(block_sema);
        }];
        
        VROAnimation::beginImplicitAnimation();
        VROAnimation::updateT();
        
        // Obtain a renderPassDescriptor generated from the view's drawable textures
        MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
        
        
        _renderContext->setCommandBuffer(commandBuffer);
        //_renderContext->setRenderEncoder(renderEncoder);
        
        if (renderPassDescriptor != nil) {
            if (self.vrModeEnabled) {
                if (_distortionCorrectionEnabled) {
                    id <MTLRenderCommandEncoder> eyeRenderEncoder = _distortionRenderer->bindEyeRenderTarget(*_renderContext);
                    _renderContext->setRenderEncoder(eyeRenderEncoder);
                    
                    [self drawFrameWithHeadTransform:_headTransform
                                             leftEye:_leftEye
                                            rightEye:_rightEye
                                       renderEncoder:eyeRenderEncoder];
                    [eyeRenderEncoder endEncoding];
                    
                    id <MTLRenderCommandEncoder> screenRenderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];
                    screenRenderEncoder.label = @"ScreenRenderEncoder";
                    
                    _renderContext->setRenderEncoder(screenRenderEncoder);
                    _distortionRenderer->renderEyesToScreen(*_renderContext);
                    
                    [screenRenderEncoder endEncoding];
                }
                else {
                    [self drawFrameWithHeadTransform:_headTransform
                                             leftEye:_leftEye
                                            rightEye:_rightEye
                                       renderEncoder:nil];
                }
            }
            else {
                [self drawFrameWithHeadTransform:_headTransform
                                         leftEye:_monocularEye
                                        rightEye:nullptr
                                   renderEncoder:nil];
            }
            
            //[renderEncoder endEncoding];
            [commandBuffer presentDrawable:view.currentDrawable];
        }
        
        // Finalize rendering here & push the command buffer to the GPU
        [commandBuffer commit];
        VROAnimation::commitAll();
    }
}

- (void)calculateFrameParametersWithHeadTransform:(VROHeadTransform *)headTransform
                                          leftEye:(VROEye *)leftEye
                                         rightEye:(VROEye *)rightEye
                                     monocularEye:(VROEye *)monocularEye {
    const VRODevice &device = _headMountedDisplay->getDevice();
    
    headTransform->setHeadView(_headTracker->getLastHeadView());
    float halfInterLensDistance = device.getInterLensDistance() * 0.5f;
    
    if (self.vrModeEnabled) {
        matrix_float4x4 leftEyeTranslate = matrix_float4x4_from_GL(GLKMatrix4MakeTranslation(halfInterLensDistance, 0, 0));
        matrix_float4x4 rightEyeTranslate = matrix_float4x4_from_GL(GLKMatrix4MakeTranslation(-halfInterLensDistance, 0, 0));
        
        leftEye->setEyeView( matrix_multiply(leftEyeTranslate, headTransform->getHeadView()));
        rightEye->setEyeView( matrix_multiply(rightEyeTranslate, headTransform->getHeadView()));
    }
    else {
        monocularEye->setEyeView(headTransform->getHeadView());
    }
    
    if (_projectionChanged) {
        const VROScreen &screen = _headMountedDisplay->getScreen();
        monocularEye->setViewport(0, 0, screen.getWidth(), screen.getHeight());
        
        if (!self.vrModeEnabled) {
            [self updateMonocularEye:monocularEye];
        }
        else if (_distortionCorrectionEnabled) {
            [self updateLeftEye:leftEye rightEye:rightEye];
            _distortionRenderer->fovDidChange(_headMountedDisplay, leftEye->getFOV(), rightEye->getFOV(), [self virtualEyeToScreenDistance]);
        }
        else {
            [self updateUndistortedFOVAndViewport];
        }
        
        leftEye->setProjectionChanged();
        rightEye->setProjectionChanged();
        monocularEye->setProjectionChanged();
        
        _projectionChanged = NO;
    }
    
    if (self.distortionCorrectionEnabled && _distortionRenderer->viewportsChanged()) {
        _distortionRenderer->updateViewports(leftEye, rightEye);
    }
}

- (void)updateMonocularEye:(VROEye *)monocularEye {
    const VROScreen &screen = _headMountedDisplay->getScreen();
    const float monocularBottomFov = 22.5f;
    const float monocularLeftFov = GLKMathRadiansToDegrees(
                                                           atanf(
                                                                 tanf(GLKMathDegreesToRadians(monocularBottomFov))
                                                                 * screen.getWidthInMeters()
                                                                 / screen.getHeightInMeters()));
    monocularEye->setFOV(monocularLeftFov, monocularLeftFov, monocularBottomFov, monocularBottomFov);
}

- (void)updateLeftEye:(VROEye *)leftEye rightEye:(VROEye *)rightEye {
    const VRODevice &device = _headMountedDisplay->getDevice();
    const VROScreen &screen = _headMountedDisplay->getScreen();
    
    const VRODistortion &distortion = device.getDistortion();
    float eyeToScreenDistance = [self virtualEyeToScreenDistance];
    
    float outerDistance = (screen.getWidthInMeters() - device.getInterLensDistance() ) / 2.0f;
    float innerDistance = device.getInterLensDistance() / 2.0f;
    float bottomDistance = device.getVerticalDistanceToLensCenter() - screen.getBorderSizeInMeters();
    float topDistance = screen.getHeightInMeters() + screen.getBorderSizeInMeters() - device.getVerticalDistanceToLensCenter();
    
    float outerAngle = GLKMathRadiansToDegrees(atanf(distortion.distort(outerDistance / eyeToScreenDistance)));
    float innerAngle = GLKMathRadiansToDegrees(atanf(distortion.distort(innerDistance / eyeToScreenDistance)));
    float bottomAngle = GLKMathRadiansToDegrees(atanf(distortion.distort(bottomDistance / eyeToScreenDistance)));
    float topAngle = GLKMathRadiansToDegrees(atanf(distortion.distort(topDistance / eyeToScreenDistance)));
    
    leftEye->setFOV(MIN(outerAngle, device.getMaximumLeftEyeFOV().getLeft()),
                    MIN(innerAngle, device.getMaximumLeftEyeFOV().getRight()),
                    MIN(bottomAngle, device.getMaximumLeftEyeFOV().getBottom()),
                    MIN(topAngle, device.getMaximumLeftEyeFOV().getTop()));
    
    const VROFieldOfView &leftEyeFov = leftEye->getFOV();
    rightEye->setFOV(leftEyeFov.getRight(),
                     leftEyeFov.getLeft(),
                     leftEyeFov.getBottom(),
                     leftEyeFov.getTop());
}

- (void)updateUndistortedFOVAndViewport {
    const VRODevice &device = _headMountedDisplay->getDevice();
    const VROScreen &screen = _headMountedDisplay->getScreen();
    
    float halfInterLensDistance = device.getInterLensDistance() * 0.5f;
    float eyeToScreenDistance = [self virtualEyeToScreenDistance];

    float left = screen.getWidthInMeters() / 2.0f - halfInterLensDistance;
    float right = halfInterLensDistance;
    float bottom = device.getVerticalDistanceToLensCenter() - screen.getBorderSizeInMeters();
    float top = screen.getBorderSizeInMeters() + screen.getHeightInMeters() - device.getVerticalDistanceToLensCenter();
    
    
    _leftEye->setFOV(GLKMathRadiansToDegrees(atan2f(left, eyeToScreenDistance)),
                     GLKMathRadiansToDegrees(atan2f(right, eyeToScreenDistance)),
                     GLKMathRadiansToDegrees(atan2f(bottom, eyeToScreenDistance)),
                    GLKMathRadiansToDegrees(atan2f(top, eyeToScreenDistance)));
    
    const VROFieldOfView &leftEyeFov = _leftEye->getFOV();
    _rightEye->setFOV(leftEyeFov.getRight(),
                      leftEyeFov.getLeft(),
                      leftEyeFov.getBottom(),
                      leftEyeFov.getTop());
    
    _leftEye->setViewport(0, 0, screen.getWidth() / 2, screen.getHeight());
    _rightEye->setViewport(screen.getWidth() / 2, 0, screen.getWidth() / 2, screen.getHeight());
}

- (float)virtualEyeToScreenDistance {
    return _headMountedDisplay->getDevice().getScreenToLensDistance();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateRenderViewSize:self.view.bounds.size];
}

#pragma mark Stereo renderer methods

- (void)updateRenderViewSize:(CGSize)size {
    if (self.vrModeEnabled) {
        [self.stereoRendererDelegate renderViewDidChangeSize:CGSizeMake(size.width / 2, size.height) context:_renderContext];
    }
    else {
        [self.stereoRendererDelegate renderViewDidChangeSize:CGSizeMake(size.width, size.height) context:_renderContext];
    }
}

- (void)drawFrameWithHeadTransform:(VROHeadTransform *)headTransform
                           leftEye:(VROEye *)leftEye
                          rightEye:(VROEye *)rightEye
                     renderEncoder:(id <MTLRenderCommandEncoder>)renderEncoder {
    
    [self.stereoRendererDelegate prepareNewFrameWithHeadViewMatrix:headTransform->getHeadView()];
    
    MTLViewport leftEyeViewport;
    leftEyeViewport.originX = leftEye->getViewport().getX();
    leftEyeViewport.originY = leftEye->getViewport().getY();
    leftEyeViewport.width   = leftEye->getViewport().getWidth();
    leftEyeViewport.height  = leftEye->getViewport().getHeight();
    leftEyeViewport.znear   = 0.0;
    leftEyeViewport.zfar    = 1.0;
    
    MTLScissorRect leftEyeScissor;
    leftEyeScissor.x = leftEye->getViewport().getX();
    leftEyeScissor.y = leftEye->getViewport().getY();
    leftEyeScissor.width = leftEye->getViewport().getWidth();
    leftEyeScissor.height = leftEye->getViewport().getHeight();

    [renderEncoder setViewport:leftEyeViewport];
    [renderEncoder setScissorRect:leftEyeScissor];
    
    _leftEyeWrapper.eye = leftEye;
    [self.stereoRendererDelegate renderEye:_leftEyeWrapper context:_renderContext];
    
    if (rightEye == nullptr) { return; }
    
    MTLViewport rightEyeViewport;
    rightEyeViewport.originX = rightEye->getViewport().getX();
    rightEyeViewport.originY = rightEye->getViewport().getY();
    rightEyeViewport.width   = rightEye->getViewport().getWidth();
    rightEyeViewport.height  = rightEye->getViewport().getHeight();
    rightEyeViewport.znear   = 0.0;
    rightEyeViewport.zfar    = 1.0;
    
    MTLScissorRect rightEyeScissor;
    rightEyeScissor.x = rightEye->getViewport().getX();
    rightEyeScissor.y = rightEye->getViewport().getY();
    rightEyeScissor.width = rightEye->getViewport().getWidth();
    rightEyeScissor.height = rightEye->getViewport().getHeight();
    
    [renderEncoder setViewport:rightEyeViewport];
    [renderEncoder setScissorRect:rightEyeScissor];
    
    _rightEyeWrapper.eye = rightEye;
    [self.stereoRendererDelegate renderEye:_rightEyeWrapper context:_renderContext];
}

@end
