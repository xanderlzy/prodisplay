// Private CoreGraphics API used to create virtual displays (macOS 11+).
// Not part of the public SDK; may change between macOS releases.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplay;

@interface CGVirtualDisplayDescriptor : NSObject
@property (copy, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
// Colour primaries and white point (CIE xy). Without them macOS 27 offers the display no modes.
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (copy, nonatomic, nullable) void (^terminationHandler)(id _Nullable, CGVirtualDisplay * _Nullable);
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) NSUInteger width;
@property (readonly, nonatomic) NSUInteger height;
@property (readonly, nonatomic) CGFloat refreshRate;
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
@property (readonly, nonatomic) unsigned int hiDPI;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// SkyLight's display mode description (layout as used by displayplacer). The functions that
// fill it are loaded at runtime. macOS 27 no longer lists virtual displays' modes through
// CGDisplayCopyAllDisplayModes, but SkyLight still does.
typedef union {
    uint8_t rawData[0xDC];
    struct {
        uint32_t mode;
        uint32_t flags;
        uint32_t width;
        uint32_t height;
        uint32_t depth;
        uint32_t dc2[42];
        uint16_t dc3;
        uint16_t freq;
        uint32_t dc4[4];
        float density;
    } derived;
} PDDisplayModeDescription;

NS_ASSUME_NONNULL_END
