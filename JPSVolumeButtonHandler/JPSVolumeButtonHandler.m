//
//  JPSVolumeButtonHandler.m
//  JPSImagePickerController
//
//  Created by JP Simard on 1/31/2014.
//  Copyright (c) 2014 JP Simard. All rights reserved.
//

#import "JPSVolumeButtonHandler.h"
#import <MediaPlayer/MediaPlayer.h>

// Comment/uncomment out NSLog to enable/disable logging
#define JPSLog(fmt, ...) //NSLog(fmt, __VA_ARGS__)

#define volumeStep 0.06250f

static NSString *const sessionVolumeKeyPath = @"outputVolume";
static void *sessionContext                 = &sessionContext;
static CGFloat maxVolume                    = 0.99999f - volumeStep;
static CGFloat minVolume                    = 0.00001f + volumeStep;

@interface JPSVolumeButtonHandler ()

@property (nonatomic, assign) CGFloat          initialVolume;
@property (nonatomic, strong) MPVolumeView   * volumeView;
@property (nonatomic, assign) BOOL             appIsActive;
@property (nonatomic, assign) BOOL             isStarted;
@property (nonatomic, assign) BOOL             disableSystemVolumeHandler;
@property (nonatomic, assign) BOOL             isAdjustingInitialVolume;
@property (nonatomic, assign) BOOL             exactJumpsOnly;
@property (nonatomic, assign) BOOL             inBackground;
@property (nonatomic, assign) CGFloat          userVolume;

@end

@implementation JPSVolumeButtonHandler

#pragma mark - Init

- (id)init {
    NSLog(@"APP IN INIT");
    self = [super init];
    
    if (self) {
        _appIsActive = YES;
        _sessionCategory = AVAudioSessionCategoryPlayback;
        _sessionOptions = AVAudioSessionCategoryOptionMixWithOthers;

        _volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(MAXFLOAT, MAXFLOAT, 0, 0)];

        [[UIApplication sharedApplication].windows.firstObject addSubview:_volumeView];
        
        _volumeView.hidden = YES;

        _exactJumpsOnly = NO;
        _session = [AVAudioSession sharedInstance];
        _userVolume = self.session.outputVolume;
        NSLog(@"APP IN VOLUME IS: %f", self.userVolume);
    }
    return self;
}

- (void)dealloc {
    NSLog(@"APP IN DEALLOC");
    [self stopHandler];
    
    MPVolumeView *volumeView = self.volumeView;
    dispatch_async(dispatch_get_main_queue(), ^{
        [volumeView removeFromSuperview];
    });
}

- (void)startHandler:(BOOL)disableSystemVolumeHandler {
    NSLog(@"APP IN STARTHANDLER");
    [self setupSession];
    self.volumeView.hidden = NO; // Start visible to prevent changes made during setup from showing default volume
    self.disableSystemVolumeHandler = disableSystemVolumeHandler;

    // There is a delay between setting the volume view before the system actually disables the HUD
    [self performSelector:@selector(setupSession) withObject:nil afterDelay:1];
}

- (void)stopHandler {
    NSLog(@"APP IN STOPHANDLER");
    if (!self.isStarted) {
        // Prevent stop process when already stop
        return;
    }
    
    self.isStarted = NO;
    self.volumeView.hidden = NO;
    // https://github.com/jpsim/JPSVolumeButtonHandler/issues/11
    // http://nshipster.com/key-value-observing/#safe-unsubscribe-with-@try-/-@catch
    @try {
        [self.session removeObserver:self forKeyPath:sessionVolumeKeyPath];
    }
    @catch (NSException * __unused exception) {
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupSession {
    NSLog(@"APP IN SETUPSESSION");
    if (self.isStarted){
        // Prevent setup twice
        return;
    }
    
    self.isStarted = YES;

    NSError *error = nil;
    // this must be done before calling setCategory or else the initial volume is reset
    [self setInitialVolume];
    [self.session setCategory:_sessionCategory
                  withOptions:_sessionOptions
                        error:&error];
    if (error) {
        JPSLog(@"%@", error);
        return;
    }
    [self.session setActive:YES error:&error];
    if (error) {
        JPSLog(@"%@", error);
        return;
    }

    // Observe outputVolume
    [self.session addObserver:self
                   forKeyPath:sessionVolumeKeyPath
                      options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
                      context:sessionContext];

    // Audio session is interrupted when you send the app to the background,
    // and needs to be set to active again when it goes to app goes back to the foreground
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidChangeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    self.volumeView.hidden = !self.disableSystemVolumeHandler;
}

- (void) useExactJumpsOnly:(BOOL)enabled{
    _exactJumpsOnly = enabled;
}

- (void)audioSessionInterrupted:(NSNotification*)notification {
    NSLog(@"APP IN AUDIOSESSIONINTERRUPTED");
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger interuptionType = [[interuptionDict valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];
    switch (interuptionType) {
        case AVAudioSessionInterruptionTypeBegan:
            JPSLog(@"Audio Session Interruption case started.", nil);
            break;
        case AVAudioSessionInterruptionTypeEnded:
        {
            JPSLog(@"Audio Session Interruption case ended.", nil);
            NSError *error = nil;
            [self.session setActive:YES error:&error];
            if (error) {
                JPSLog(@"%@", error);
            }
            break;
        }
        default:
            JPSLog(@"Audio Session Interruption Notification case default.", nil);
            break;
    }
}

- (void)setInitialVolume {
    NSLog(@"APP IN SETINITIALVOLUME");
//    self.initialVolume = self.session.outputVolume;
//    NSLog(@"APP IN ACTUAL VOLUME IS: %f", self.initialVolume);
//    if (self.initialVolume > maxVolume) {
//        self.initialVolume = maxVolume;
//        self.isAdjustingInitialVolume = YES;
//        if (_volumeView) {
//            [self setSystemVolume:self.initialVolume];
//        }
//    } else if (self.initialVolume < minVolume) {
//        self.initialVolume = minVolume;
//        self.isAdjustingInitialVolume = YES;
//        if (_volumeView) {
//            [self setSystemVolume:self.initialVolume];
//        }
//    }
    self.isAdjustingInitialVolume = YES;
    if (self.session.outputVolume == 0.50000) {
        if (_volumeView) {
            [self setSystemVolume:0.30000];
        }
    } else {
        if (_volumeView) {
            [self setSystemVolume:0.50000];
        }
    }
}

- (void)applicationDidChangeActive:(NSNotification *)notification {
    NSLog(@"APP IN applicationDidChangeActive");
    self.inBackground = NO;
    self.appIsActive = [notification.name isEqualToString:UIApplicationDidBecomeActiveNotification];
    if (!self.isStarted) return;
    if (self.appIsActive ) {
        [self setInitialVolume];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    NSLog(@"APP IN applicationWillResignActive");
    self.inBackground = YES;
    if (_volumeView) {
        [self setSystemVolume:self.userVolume];
    }
}

#pragma mark - Convenience

+ (instancetype)volumeButtonHandlerWithUpBlock:(JPSVolumeButtonBlock)upBlock downBlock:(JPSVolumeButtonBlock)downBlock {
    NSLog(@"APP IN volumeButtonHandlerWithUpBlock");
    JPSVolumeButtonHandler *instance = [[JPSVolumeButtonHandler alloc] init];
    if (instance) {
        instance.upBlock = upBlock;
        instance.downBlock = downBlock;
    }
    return instance;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSLog(@"APP IN observeValueForKEYPAth");
    if (context == sessionContext) {
        CGFloat oldVolume = [change[NSKeyValueChangeOldKey] floatValue];
        CGFloat newVolume = [change[NSKeyValueChangeNewKey] floatValue];
        JPSLog(@"Volume change detected: %f -> %f", oldVolume, newVolume);
        NSLog(@"APP IN A");
        if (self.inBackground) {
            return;
        }
        NSLog(@"APP IN B");
        if (!self.appIsActive) {
            // Probably control center, skip blocks
            return;
        }
        NSLog(@"APP IN C");
        if (self.isAdjustingInitialVolume) {
            self.isAdjustingInitialVolume = NO;
            return;
        }
        NSLog(@"APP IN D");
        CGFloat difference = fabs(newVolume-oldVolume);

        JPSLog(@"Old Vol:%f New Vol:%f Difference = %f", (double)oldVolume, (double)newVolume, (double) difference);

        if (_exactJumpsOnly && difference < .062 && (newVolume == 1. || newVolume == 0)) {
            JPSLog(@"Using a non-standard Jump of %f (%f-%f) which is less than the .0625 because a press of the volume button resulted in hitting min or max volume", difference, oldVolume, newVolume);
        } else if (_exactJumpsOnly && (difference > .063 || difference < .062)) {
            JPSLog(@"Ignoring non-standard Jump of %f (%f-%f), which is not the .0625 a press of the actually volume button would have resulted in.", difference, oldVolume, newVolume);
            [self setInitialVolume];
            return;
        }
        NSLog(@"APP IN E");
        if (newVolume > oldVolume) {
            if (self.upBlock) self.upBlock();
        } else {
            if (self.downBlock) self.downBlock();
        }

        if (!self.disableSystemVolumeHandler) {
            // Don't reset volume if default handling is enabled
            return;
        }

        // Reset volume
        if (_volumeView) {
            NSLog(@"APP IN F");
            [self setInitialVolume];
        }
        JPSLog(@"Restoring volume to %f (actual: %f)", self.initialVolume, self.session.outputVolume);
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - System Volume

- (void)setSystemVolume:(CGFloat)volume {
    NSLog(@"APP IN setSystemVolume");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MPMusicPlayerController applicationMusicPlayer] setVolume:(float)volume];
        NSLog(@"APP IN Changed volume to %f (actual: %f)", volume, self.session.outputVolume);
    });
#pragma clang diagnostic pop
}

@end
