//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THPlayerController.h"
#import "THThumbnail.h"
#import <AVFoundation/AVFoundation.h>
#import "THTransport.h"
#import "THPlayerView.h"
#import "AVAsset+THAdditions.h"
#import "UIAlertView+THAdditions.h"
#import "THNotifications.h"
#import "THThumbnail.h"

// AVPlayerItem's status property
#define STATUS_KEYPATH @"status"

// Refresh interval for timed observations of AVPlayer
#define REFRESH_INTERVAL 0.5f

// Define this constant for the key-value observation context.
static const NSString *PlayerItemStatusContext;


@interface THPlayerController () <THTransportDelegate>


// Listing 4.4
@property (strong, nonatomic) AVAsset *asset;
@property (strong, nonatomic) AVPlayerItem *playerItem;
@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) THPlayerView *playerView;

@property (weak, nonatomic) id <THTransport> transport;

@property (strong, nonatomic) id timeObserver;
@property (strong, nonatomic) id itemEndObserver;
@property (assign, nonatomic) float lastPlaybackRate;

@property (strong, nonatomic) AVAssetImageGenerator *imageGenerator;

@end

@implementation THPlayerController

#pragma mark - Setup

- (id)initWithURL:(NSURL *)assetURL {
    self = [super init];
    if (self) {
        
        // Listing 4.6
        _asset = [AVAsset assetWithURL:assetURL];                   // 1
        [self prepareToPlay];
    }
    return self;
}

- (void)prepareToPlay {

    // Listing 4.6
    NSArray *keys = @[@"tracks", @"duration", @"commonMetadata", @"availableMediaCharacteristicsWithMediaSelectionOptions"];
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset         automaticallyLoadedAssetKeys:keys];                              // 2
    
    [self.playerItem addObserver:self forKeyPath:STATUS_KEYPATH options:0    context:&PlayerItemStatusContext];                                 // 3
    
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];          // 4
    
     self.playerView = [[THPlayerView alloc] initWithPlayer:self.player];
     self.transport = self.playerView.transport;
     self.transport.delegate = self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    
    // Listing 4.7
    if (context == &PlayerItemStatusContext) {
        dispatch_async(dispatch_get_main_queue(), ^{                            // 1
            [self.playerItem removeObserver:self forKeyPath:STATUS_KEYPATH];
            
            if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                // set up time observers                                        // 2
                [self addPlayerItemTimeObserver];
                [self addItemEndObserverForPlayerItem];
                
                CMTime duration = self.playerItem.duration;
                
                // Synchronize the time display                                 // 3
                [self.transport setCurrentTime:CMTimeGetSeconds(kCMTimeZero) duration:CMTimeGetSeconds(duration)];
                
                // Set the video title.
                [self.transport setTitle:self.asset.title];                     // 4
                
                [self.player play];                                         // 5
                
                [self generateThumbnails];
                [self loadMediaOptions];
            } else {
                // show error
            }
        });
    }
}

#pragma mark - Time Observers

- (void)addPlayerItemTimeObserver {

    // Listing 4.8
    // Create 0.5 second refresh interval - REFRESH_INTERVAL == 0.5
    CMTime interval = CMTimeMakeWithSeconds(REFRESH_INTERVAL, NSEC_PER_SEC);  // 1
    
    // Main dispatch queue
    dispatch_queue_t queue = dispatch_get_main_queue();                         // 2
    
    // Create callback block for time observer
    __weak THPlayerController *weakSelf = self;
    void (^callback)(CMTime time) = ^(CMTime time) {
        NSTimeInterval currentTime = CMTimeGetSeconds(time);
        NSTimeInterval duration = CMTimeGetSeconds(weakSelf.playerItem.duration);
        [weakSelf.transport setCurrentTime:currentTime duration:duration];
    };
    
    // Add observer and store pointer for future use
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:interval queue:queue usingBlock:callback];
}

- (void)addItemEndObserverForPlayerItem {

    // Listing 4.9
    NSString *name = AVPlayerItemDidPlayToEndTimeNotification;
    
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    
    __weak THPlayerController *weakSelf = self;                     // 1
    void (^callback)(NSNotification *note) = ^(NSNotification *notification) {
        [weakSelf.player seekToTime:kCMTimeZero                     // 2
                  completionHandler:^(BOOL finished) {
            [weakSelf.transport playbackComplete];                  // 3
        }];
    };
    
    self.itemEndObserver = [[NSNotificationCenter defaultCenter]   // 4
                            addObserverForName:name object:self.playerItem queue:queue usingBlock:callback];
}

- (void)dealloc {
    if (self.itemEndObserver) {                                     // 5
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self.itemEndObserver name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        self.itemEndObserver = nil;
    }
}

#pragma mark - THTransportDelegate Methods

- (void)play {

    // Listing 4.10
    [self.player play];
}

- (void)pause {

    // Listing 4.10
    self.lastPlaybackRate = self.player.rate;
    [self.player pause];
    
}

- (void)stop {

    // Listing 4.10
    [self.player setRate:0.0f];
    [self.transport playbackComplete];
    
}

- (void)jumpedToTime:(NSTimeInterval)time {

    // Listing 4.10
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
}

- (void)scrubbingDidStart {                         // 1

    // Listing 4.11
    self.lastPlaybackRate = self.player.rate;
    [self.player pause];
    [self.player removeTimeObserver:self.timeObserver];
}

- (void)scrubbedToTime:(NSTimeInterval)time {       // 2

    // Listing 4.11
    [self.playerItem cancelPendingSeeks];
    [self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
    
}

- (void)scrubbingDidEnd {           // 3

    // Listing 4.11
    [self addPlayerItemTimeObserver];
    if (self.lastPlaybackRate > 0.0f) {
        [self.player play];
    }
}


#pragma mark - Thumbnail Generation

- (void)generateThumbnails {

    // Listing 4.14
    self.imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];                            // 1
    
    // Generate the @2x equivalent
    self.imageGenerator.maximumSize = CGSizeMake(200.0f, 0.0f);             // 2

    CMTime duration = self.asset.duration;
    
    NSMutableArray *times = [NSMutableArray array];                         // 3
    CMTimeValue increment = duration.value / 20;
    CMTimeValue currentValue = 2.0 * duration.timescale;
    while (currentValue <= duration.value) {
        CMTime time = CMTimeMake(currentValue, duration.timescale);
        [times addObject:[NSValue valueWithCMTime:time]];
        currentValue += increment;
    }
    
    __block NSUInteger imageCount = times.count;                            // 4
    __block NSMutableArray *images = [NSMutableArray array];
    
    AVAssetImageGeneratorCompletionHandler handler;                         // 5
    
    handler = ^(CMTime requestedTime,
                CGImageRef imageRef,
                CMTime actualTime,
                AVAssetImageGeneratorResult result,
                NSError *error) {
        
        if (result == AVAssetImageGeneratorSucceeded) {                     // 6
            UIImage *image = [UIImage imageWithCGImage:imageRef];
            id thumbnail = [THThumbnail thumbnailWithImage: image time: actualTime];
            [images addObject:thumbnail];
        } else {
            NSLog(@"Failed to create thumbnail image.");
        }
        
        // If the decremented image count is at 0, we're all done.
        if (--imageCount == 0) {                                            // 7
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *name = THThumbnailsGeneratedNotification;
                NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
                [nc postNotificationName:name object:images];
            });
        }
    };
    
    [self.imageGenerator generateCGImagesAsynchronouslyForTimes:times        completionHandler:handler];
}


- (void)loadMediaOptions {

    // Listing 4.16
    NSString *mc = AVMediaCharacteristicLegible;                        // 1
    AVMediaSelectionGroup *group = [self.asset mediaSelectionGroupForMediaCharacteristic:mc];                   // 2
    if (group) {
        NSMutableArray *subtitles = [NSMutableArray array];             // 3
        for (AVMediaSelectionOption *option in group.options) {
            [subtitles addObject:option.displayName];
        }
        [self.transport setSubtitles: subtitles];                       // 4
    } else {
        [self.transport setSubtitles: nil];
    }
}

- (void)subtitleSelected:(NSString *)subtitle {

    // Listing 4.17
    NSString *mc = AVMediaCharacteristicLegible;
    AVMediaSelectionGroup *group = [self.asset mediaSelectionGroupForMediaCharacteristic:mc];
    BOOL selected = NO;
    for (AVMediaSelectionOption *option in group.options) {
        if ([option.displayName isEqualToString:subtitle]) {
            [self.playerItem selectMediaOption:option inMediaSelectionGroup:group];
            selected = YES;
        }
    }
    if (!selected) {
        [self.playerItem selectMediaOption:nil inMediaSelectionGroup:group];
    }
}


#pragma mark - Housekeeping

- (UIView *)view {
    return self.playerView;
}

@end
