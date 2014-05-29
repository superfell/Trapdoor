//
//  GDGradient.h
//

#import <Cocoa/Cocoa.h>


@interface GDGradient : NSObject {
    CGColorSpaceRef m_colorSpace;
    CGFunctionRef   m_shadingFunction;
    NSColor*        m_color;
    CGFloat         m_highlight[4];
    CGFloat         m_shadow[4];
}

- (NSColor *)color;
- (void)setColor:(NSColor *)color;
- (void)getGradientColorComponents:(CGFloat[4])components forFraction:(CGFloat)fraction;
- (NSColor *)gradientColorForFraction:(CGFloat)fraction;
- (void)fillRect:(NSRect)aRect;
@end
