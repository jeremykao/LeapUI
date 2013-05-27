//
//  LUIListener.m
//  LeapUI
//
//  Created by Siddarth Sampangi on 28/04/2013.
//  Copyright (c) 2013 Siddarth Sampangi. All rights reserved.
//

#ifndef LUILISTENER

#import "LUIListener.h"
#import "LeapObjectiveC.h"
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

#define DEBUG 0

/* Cursor movement values */
#define MIN_VIEW_THRESHOLD 70
#define MIN_FREEZE_THRESHOLD 15
#define MIN_CLICK_THRESHOLD 0
#define MAX_ZSCALE_ZOOM 2.5

/* These are values that we are simply comfortable with using.
   They do not represent the Leap's full field of view. */
#define LEAP_FIELD_OF_VIEW_WIDTH 600
#define LEAP_FIELD_OF_VIEW_HEIGHT 400

@implementation LUIListener
@synthesize window = _window;

/* GENERAL VARS */
static bool clickingFinger;

/* NAVIGATION VARS */
bool moving = YES;
static LeapFrame *prevFrame;
static CGFloat fieldOfViewScale;
static CGFloat mainScreenWidth;
static CGFloat mainScreenHeight;
static bool leftClickDown = NO;
static NSDate *leftClickDownTime;
static int statusItemColor = 0; /* 1 = red; 2 = yellow; 3 = green;*/

static NSImage *red;
static NSImage *yellow;
static NSImage *green;

/* SCROLLING VARS */
static LeapVector *scrollingVelocity;

/* PINCH AND ZOOM VARS */
static float prevTipdistance = 0;
static float startSymbol=1;

/* BRIGHTNESS CONTROL VARS */
static float prevRadius=0;
static float startSymbolR=1;

/* VOLUME CONTROL VARS */
static float prevRotationAngle=0;
static float startSymbolV=1;

- (void) run{
    LeapController *controller = [[LeapController alloc] init];
    [controller addListener:self];
    [controller setPolicyFlags:LEAP_POLICY_BACKGROUND_FRAMES];
    NSLog(@"Listener added");
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:[self statusMenu]];
    //[statusItem setTitle:@"Test"];
    NSBundle *bundle = [NSBundle mainBundle];
    
    red = [[NSImage alloc]initWithContentsOfFile:[bundle pathForResource:@"red" ofType:@"jpg"] ];
    [red setSize:NSMakeSize(20, 20)];
    
    yellow = [[NSImage alloc]initWithContentsOfFile:[bundle pathForResource:@"yellow" ofType:@"jpg"] ];
    [yellow setSize:NSMakeSize(20, 20)];
    
    green = [[NSImage alloc]initWithContentsOfFile:[bundle pathForResource:@"green" ofType:@"jpg"] ];
    [green setSize:NSMakeSize(20, 20)];
    
    [red setSize:NSMakeSize(20, 20)];
    [statusItem setImage:red];
    [statusItem setHighlightMode:YES];
}

- (void) setStatusBarImage: (NSImage *) img {
    [statusItem setImage:img];
    [statusItem setHighlightMode:YES];
}

- (void)onInit:(NSNotification *)notification
{
    NSLog(@"Initialized");
}

- (void)onConnect:(NSNotification *)notification
{
    NSLog(@"Connected");
    LeapController *aController = (LeapController *)[notification object];
    //    [aController enableGesture:LEAP_GESTURE_TYPE_CIRCLE enable:YES];
    //    [aController enableGesture:LEAP_GESTURE_TYPE_KEY_TAP enable:YES];
    //    [aController enableGesture:LEAP_GESTURE_TYPE_SCREEN_TAP enable:YES];
    [aController enableGesture:LEAP_GESTURE_TYPE_SWIPE enable:YES];
    
    NSRect mainScreenFrame = [[NSScreen mainScreen] frame];
    mainScreenWidth = mainScreenFrame.size.width;
    mainScreenHeight = mainScreenFrame.size.height;
    
    
    fieldOfViewScale = mainScreenWidth/LEAP_FIELD_OF_VIEW_WIDTH;
}

- (void)onDisconnect:(NSNotification *)notification
{
    NSLog(@"Disconnected");
}

- (void)onExit:(NSNotification *)notification
{
    NSLog(@"Exited");
}

- (void) click {
    
    NSPoint mouseLoc = [NSEvent mouseLocation];
    CGPoint clickPosition = CGPointMake(mouseLoc.x, mainScreenHeight - mouseLoc.y);
    
    if(!leftClickDown) {
        CGEventRef clickLeftDown = CGEventCreateMouseEvent(
                                                       NULL, kCGEventLeftMouseDown,
                                                       clickPosition,
                                                       kCGMouseButtonLeft
                                                       );
        CGEventSetType(clickLeftDown, kCGEventLeftMouseDown);
        CGEventPost(kCGHIDEventTap, clickLeftDown);
        CFRelease(clickLeftDown);
        leftClickDown = YES;
        leftClickDownTime = [NSDate date];
    }
    else {
        CGEventRef clickLeftUp = CGEventCreateMouseEvent(
                                                       NULL, kCGEventLeftMouseUp,
                                                       clickPosition,
                                                       kCGMouseButtonLeft
                                                       );
        CGEventSetType(clickLeftUp, kCGEventLeftMouseUp);
        CGEventPost(kCGHIDEventTap, clickLeftUp);
        CFRelease(clickLeftUp);
        leftClickDown = NO;
        leftClickDownTime = [NSDate date];
    }
}

- (void) moveCursorWithFinger: (LeapFinger *) finger controller: (LeapController *) aController{
    
    /* STATUS BAR ITEM COLOR AND CLICKING */
    if(finger.tipPosition.z < MIN_CLICK_THRESHOLD) {
        if(statusItemColor != 1) {
            [self setStatusBarImage: green];
            statusItemColor = 1;
        }
        if(!leftClickDown){
            [self click];
            return;
        }
    }
    else if(finger.tipPosition.z < MIN_FREEZE_THRESHOLD){
        if(statusItemColor != 2) {
            [self setStatusBarImage: yellow];
            statusItemColor = 2;
        }
        [self setStatusBarImage:green];
        if(leftClickDown) [self click];
        return;
    }
    else {
        if(statusItemColor != 3) {
            [self setStatusBarImage: red];
            statusItemColor = 3;
        }
    }
    
    /* MOVEMENT */
    NSPoint mouseLoc = [NSEvent mouseLocation];
    LeapFrame *previousFrame;
    if(moving) previousFrame = [aController frame:1];
    else previousFrame = prevFrame;
    
    LeapFinger *prevFinger = [previousFrame finger:[finger id]];
    if(![prevFinger isValid]) return;
    
    CGFloat velocity = powf((powf(finger.tipVelocity.x,2) + powf(finger.tipVelocity.y,2)),0.5);

    CGFloat scale = velocity/100 * fieldOfViewScale * fabsf(finger.tipPosition.z) * MAX_ZSCALE_ZOOM/MIN_VIEW_THRESHOLD;
    
    CGFloat deltaX = (float) lroundf((finger.tipPosition.x - prevFinger.tipPosition.x) * scale);
    CGFloat deltaY = (float) lroundf((finger.tipPosition.y - prevFinger.tipPosition.y) * scale);
    
    if(deltaX == 0 && deltaY == 0) {
        prevFrame = previousFrame;
        moving = NO;
        return;
    }
    else moving = YES;
    
    CGFloat xpos = mouseLoc.x + deltaX;
    
    if(xpos < 0) xpos = 0;
    else if(xpos > mainScreenWidth) xpos = mainScreenWidth;
    
    CGFloat ypos = mainScreenHeight - (mouseLoc.y + deltaY);
    
    if(ypos < 0) ypos = 0;
    else if(ypos > mainScreenHeight) ypos = mainScreenHeight;
    
    CGPoint fingerTip = CGPointMake(xpos,ypos);
    
    CGEventType e;
    
    if(leftClickDown) {
        NSTimeInterval t = [[NSDate date] timeIntervalSinceDate:leftClickDownTime];
       if((int)t > 1) e = kCGEventLeftMouseDragged;
       else return;
    }
    else e = kCGEventMouseMoved;
    
    CGEventRef move = CGEventCreateMouseEvent( NULL, e,
                                               fingerTip,
                                               kCGMouseButtonLeft // ignored
                                               );
    
    if(DEBUG) {NSLog(@"\nLeapFinger location:\t%f , %f\n\t\t\tMouseXY:\t%f , %f\n\tFinal Position: \t%f, %f\n\t\t\tDeltaXY:\t%f, %f\n\t\t\tVelocity:\t%f\n\n",
                     finger.tipPosition.x, finger.tipPosition.y,
                     mouseLoc.x, mouseLoc.y,
                     fingerTip.x, fingerTip.y,
                     deltaX, deltaY,
                     velocity);
    }
    CGEventSetType(move, e);
    CGEventPost(kCGHIDEventTap, move);
    CFRelease(move);
}

- (void) scrollWithFingers: (NSMutableArray *) fingers  andController:(LeapController *) aController
{
    /**** Two Finger Scrolling ****/
    /* Still have to:
     1. put in checks to differentiate pinch to zoom as two finger scrolling when tipPosition < POSITION_DIFF_THRESHOLD (check x posiitons)
     2. recognize when user is not scrolling anymore (probably through some predictions like velocity * fps
     */
    
    LeapFrame *currentFrame = [aController frame:0];
    LeapFrame *previousFrame = [aController frame:1];
    
    LeapVector *currentTipPosition = [fingers[0] tipPosition];
    LeapVector *previousTipPosition = [previousFrame finger: [ (LeapFinger *)fingers[0] id]].tipPosition;
        
    if ( previousFrame != NULL){
        //NSLog(@"Translation Probability: %f", [frame translationProbability:comparisonFrame]);
        //NSLog(@"Distance scrolled: %f: ", [frame translation:comparisonFrame].magnitude);
       
        if([currentFrame translationProbability: previousFrame] > 0.4) {
            if (currentTipPosition.z < MIN_CLICK_THRESHOLD  ){
                CGEventRef scrollingY = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1,
                                                                      previousTipPosition.y - currentTipPosition.y);
                CGEventRef scrollingX = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2,
                                                                      previousTipPosition.x - currentTipPosition.x);
                CGEventSetType(scrollingY, kCGEventScrollWheel);
                CGEventPost(kCGHIDEventTap, scrollingY);
                CFRelease(scrollingY);
                
                CGEventSetType(scrollingX, kCGEventScrollWheel);
                CGEventPost(kCGHIDEventTap, scrollingX);
                CFRelease(scrollingX);
                
                scrollingVelocity = [fingers[0] tipVelocity];
            }
            else {
                
                //[self inertialScrollWithVelocity: scrollingVelocity];
            }
        }
    }
    /***** End Two Finger Scrolling *****/
}

//THIS DOESNT WORK YET AT ALL. WORK IN PROGRESS
- (void) inertialScrollWithVelocity: (LeapVector *) scrollingVelocity {
    if(scrollingVelocity.x <= 0.01 && scrollingVelocity.y <= 0.01) return;
    CGEventRef scrollingY = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1,
                                                          -1*scrollingVelocity.y);
    CGEventRef scrollingX = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2,
                                                          -1*scrollingVelocity.x);
    CGEventSetType(scrollingY, kCGEventScrollWheel);
    CGEventPost(kCGHIDEventTap, scrollingY);
    CFRelease(scrollingY);
    
    CGEventSetType(scrollingX, kCGEventScrollWheel);
    CGEventPost(kCGHIDEventTap, scrollingX);
    CFRelease(scrollingX);
    
    
    scrollingVelocity = [[LeapVector alloc] initWithX: scrollingVelocity.x * 0.9
                                                    y: scrollingVelocity.y * 0.9
                                                    z: scrollingVelocity.z];
}

- (void) pinchAndZoom :(NSMutableArray *)fingers
{
    Boolean symbol=false;
    if ( [fingers count] == 2 ){
        
        // BEGIN Two Finger Pinch&Zoom
        const float disThreshold = 2.5;
        float tip1Positionx = [ fingers[0] tipPosition ].x;
        float tip2Positionx = [ fingers[1] tipPosition ].x;
        float tip1Positiony = [ fingers[0] tipPosition ].y;
        float tip2Positiony = [ fingers[1] tipPosition ].y;
        float tip1Positionz = [ fingers[0] tipPosition ].z;
        float tip2Positionz = [ fingers[1] tipPosition ].z;
        float distance = sqrtf(powf((tip1Positionx-tip2Positionx), 2)+powf((tip1Positiony-tip2Positiony), 2)+powf((tip1Positionz-tip2Positionz), 2));
        //NSLog(@"distance = %f",distance);
        // NSLog(@"predistance = %f",prevTipdistance);
        if( distance - prevTipdistance > disThreshold&&startSymbol!=1)
        {
        
            NSLog(@"Zoom Gesture dectected");
            [self pressKey:kVK_Command down:true];
            [NSThread sleepForTimeInterval: 0.1]; // 100 mS delay
            [self pressKey:kVK_ANSI_Equal down:true];
            
          
            
        }
        else if ( prevTipdistance - distance > disThreshold&&startSymbol!=1){
      
            NSLog(@"Pinch Gesture dectected");
            [self pressKey:kVK_Command down:true];
            [NSThread sleepForTimeInterval: 0.1]; // 100 mS delay
            [self pressKey:kVK_ANSI_Minus down:true];
            
           
        }
        else if(startSymbol!=1)
        {
            symbol=true;
            
        }
        if(startSymbol==1)
            startSymbol--;
        if(symbol==true) // when you put 2 fingers in the field but do not recognize as zoom or pinch
            startSymbol=1;
        prevTipdistance = distance;
    }
}

- (float)getVolume {
	float			b_vol;
	OSStatus		err;
	AudioDeviceID		device;
	UInt32			size;
	UInt32			channels[2];
	float			volume[2];
	
	// get device
	size = sizeof device;
	err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &size, &device);
	if(err!=noErr) {
		NSLog(@"audio-volume error get device");
		return 0.0;
	}
	
	// try set master volume (channel 0)
	size = sizeof b_vol;
	err = AudioDeviceGetProperty(device, 0, 0, kAudioDevicePropertyVolumeScalar, &size, &b_vol);	//kAudioDevicePropertyVolumeScalarToDecibels
	if(noErr==err) return b_vol;
	
	// otherwise, try seperate channels
	// get channel numbers
	size = sizeof(channels);
	err = AudioDeviceGetProperty(device, 0, 0,kAudioDevicePropertyPreferredChannelsForStereo, &size,&channels);
	if(err!=noErr) NSLog(@"error getting channel-numbers");
	
	size = sizeof(float);
	err = AudioDeviceGetProperty(device, channels[0], 0, kAudioDevicePropertyVolumeScalar, &size, &volume[0]);
	if(noErr!=err) NSLog(@"error getting volume of channel %d",channels[0]);
	err = AudioDeviceGetProperty(device, channels[1], 0, kAudioDevicePropertyVolumeScalar, &size, &volume[1]);
	if(noErr!=err) NSLog(@"error getting volume of channel %d",channels[1]);
	
	b_vol = (volume[0]+volume[1])/2.00;
	
	return  b_vol;
}


// setting system volume
- (void)setVolume:(float)involume {
	OSStatus		err;
	AudioDeviceID		device;
	UInt32			size;
	Boolean			canset	= false;
	UInt32			channels[2];
	//float			volume[2];
    
	// get default device
	size = sizeof device;
	err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &size, &device);
	if(err!=noErr) {
		NSLog(@"audio-volume error get device");
		return;
	}
	
	
	// try set master-channel (0) volume
	size = sizeof canset;
	err = AudioDeviceGetPropertyInfo(device, 0, false, kAudioDevicePropertyVolumeScalar, &size, &canset);
	if(err==noErr && canset==true) {
		size = sizeof involume;
		err = AudioDeviceSetProperty(device, NULL, 0, false, kAudioDevicePropertyVolumeScalar, size, &involume);
		return;
	}
    
	// else, try seperate channes
	// get channels
	size = sizeof(channels);
	err = AudioDeviceGetProperty(device, 0, false, kAudioDevicePropertyPreferredChannelsForStereo, &size,&channels);
	if(err!=noErr) {
		NSLog(@"error getting channel-numbers");
		return;
	}
	
	// set volume
	size = sizeof(float);
	err = AudioDeviceSetProperty(device, 0, channels[0], false, kAudioDevicePropertyVolumeScalar, size, &involume);
	if(noErr!=err) NSLog(@"error setting volume of channel %d",channels[0]);
	err = AudioDeviceSetProperty(device, 0, channels[1], false, kAudioDevicePropertyVolumeScalar, size, &involume);
	if(noErr!=err) NSLog(@"error setting volume of channel %d",channels[1]);
	
}

-(void)brightnessControl:(LeapHand *)hands andFinger:(NSMutableArray *) fingers;
{
    if([fingers count]==5){
      
    float radius= [hands sphereRadius];
         // NSLog(@"current radius= %f",radius);
       // NSLog(@"prevradius = %f",prevRadius);
    const float radiusthreshold=2.2;
    if(radius - prevRadius>=radiusthreshold)
    {
        //NSLog(@"Increase the Brightness");
        //[self setVolume: [self getVolume] +0.05];
            }
    else if(prevRadius - radius>=radiusthreshold)
    {
       // NSLog(@"Decrease the Brightness");
       // [self setVolume: [self getVolume] -0.05];
    }
    prevRadius=radius;
    }
}
-(void)volumeControl:(LeapHand *)hands andController:(LeapController *) aController
{
    LeapFrame *prevFrame = [aController frame: 1];
    
    Boolean symbol=false;
    float rotationAngle=0;
    const float rotationThreshold=0.05;
    if(startSymbolV!=1){
    LeapVector *axis=[[LeapVector alloc]init];
    axis=[hands rotationAxis:prevFrame];
     rotationAngle=[hands rotationAngle:prevFrame];
        if(rotationAngle-prevRotationAngle>=rotationThreshold)
        {
            NSLog(@"Increase the Volume");
            
        }
       else if(prevRotationAngle-rotationAngle>=rotationThreshold)
       {
           NSLog(@"Decrease the Volume");
       }
        else{
    symbol=true;
        }

        }
    if(startSymbolV==1)
        startSymbolV--;
    if(symbol==true)
        startSymbolV=1;
    prevRotationAngle=rotationAngle;
    NSLog(@"rotationAngle= %f",rotationAngle);

}

- (void)onFrame:(NSNotification *)notification;
{
    LeapController *aController = (LeapController *)[notification object];
    
    // Get the most recent frame and report some basic information
    LeapFrame *frame = [aController frame:0];
     LeapHand *hand;
    if([[frame hands]count]!=0)
    {
        hand=[[frame hands] objectAtIndex:0];
            
    }

    //if the finger is more than MIN_VIEW_THRESHOLD millimeters away from the front of the Leap, then ignore it
    NSMutableArray *fingers = [[NSMutableArray alloc] initWithArray:[frame fingers]];
    for(int i = 0; i < [fingers count]; i++) {
        if(((LeapFinger*)[fingers objectAtIndex:i]).tipPosition.z > MIN_VIEW_THRESHOLD){
            //NSLog(@"Removing finger with distance: %f", [(LeapFinger*)[fingers objectAtIndex:i] tipPosition].z);
            [fingers removeObjectAtIndex:i];
            i--;
        }
        else if(((LeapFinger*)[fingers objectAtIndex:i]).tipPosition.z < MIN_CLICK_THRESHOLD){
            clickingFinger = true;
        }
    }
    
    //Point and Click will be 1 finger; Pinch to zoom and Two finger scroll will be 2 fingers;
    
    NSUInteger fingerCount = [fingers count];
    
    if(fingerCount==0)
    {
        startSymbol=1;
        startSymbolV=1;
        startSymbolR=1;
    }
    
    else if(fingerCount == 1) {
        [self moveCursorWithFinger: [fingers objectAtIndex:0] controller: aController];
    }
    else if(fingerCount == 2) {
        if([frame scaleProbability:[aController frame:1] ] > [frame translationProbability:[aController frame:1]]) {
            [self pinchAndZoom:fingers];
        }
        else {
            [self scrollWithFingers: fingers andController: aController];
        }
    }
    else if (fingerCount>=3)
    {
        [self volumeControl:hand andController:aController];
    }
    else if(fingerCount == 5) {
        //Sid: This can be changed later
       /* CGEventRef move = CGEventCreateMouseEvent( NULL, kCGEventMouseMoved,
                                                  CGPointMake(mainScreenWidth/2, mainScreenHeight/2),
                                                  kCGMouseButtonLeft // ignored
                                                  );
        CGEventSetType(move, kCGEventMouseMoved);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);*/
        [self brightnessControl:hand andFinger:fingers];
        
    }
    else {
        //NSLog(@"Nothing significant is happening");
    }

}
-(void) pressKey:(int)key down:(BOOL)pressDown{
    CGEventRef downEvent = CGEventCreateKeyboardEvent(NULL, key, pressDown);
    
    CGEventPost(kCGHIDEventTap, downEvent);
    
    CFRelease(downEvent);
}
@end

#endif //LUILISTENER
