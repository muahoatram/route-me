//
//  RMPath.m
//
// Copyright (c) 2008, Route-Me Contributors
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "RMPath.h"
#import "RMMapView.h"
#import "RMMapContents.h"
#import "RMMercatorToScreenProjection.h"
#import "RMPixel.h"
#import "RMProjection.h"

@implementation RMPath

@synthesize origin;

- (id) initWithContents: (RMMapContents*)aContents
{
	if (![super init])
		return nil;
	
	contents = aContents;
	
	lineWidth = 100.0f;
	drawingMode = kCGPathFillStroke;
	lineColor = [UIColor blackColor];
	fillColor = [UIColor redColor];
	self.masksToBounds = NO;
	
	scaleLineWidth = YES;
	boundsInMercators = CGRectZero;
//	self.frame = CGRectMake(100, 100, 100, 100);
//	[self setNeedsDisplayOnBoundsChange:YES];
	
	return self;
}

- (id) initForMap: (RMMapView*)map
{
	return [self initWithContents:[map contents]];
}

-(void) dealloc
{
	CGPathRelease(path);
    [self setLineColor:nil];
    [self setFillColor:nil];
    [points release];
    points = nil;
	
	[super dealloc];
}

- (id<CAAction>)actionForKey:(NSString *)key
{
	return nil;
}

- (void) recalculateGeometry
{
	float scale = [[contents mercatorToScreenProjection] scale];
	float scaledLineWidth;
	CGPoint myPosition;
	CGRect pixelBounds, screenBounds;
	float offset;
	const float outset = 100.0f; // provides a buffer off screen edges for when path is scaled or moved

	scaledLineWidth = lineWidth;
	if(!scaleLineWidth) {
		renderedScale = [contents scale];
		scaledLineWidth *= renderedScale;
	}
	pixelBounds = CGRectInset(boundsInMercators, -scaledLineWidth, -scaledLineWidth);

	pixelBounds = RMScaleCGRectAboutPoint(pixelBounds, 1.0f / scale, CGPointZero);

	// Clip bound rect to screen bounds.
	// If bounds are not clipped, they won't display when you zoom in too much.
	myPosition = [[contents mercatorToScreenProjection] projectXYPoint: origin];
	screenBounds = [contents screenBounds];

	// Clip top
	offset = myPosition.y + pixelBounds.origin.y - screenBounds.origin.y + outset;
	if(offset < 0.0f) {
		pixelBounds.origin.y -= offset;
		pixelBounds.size.height += offset;
	}
	// Clip left
	offset = myPosition.x + pixelBounds.origin.x - screenBounds.origin.x + outset;
	if(offset < 0.0f) {
		pixelBounds.origin.x -= offset;
		pixelBounds.size.width += offset;
	}
	// Clip bottom
	offset = myPosition.y + pixelBounds.origin.y + pixelBounds.size.height - screenBounds.origin.y - screenBounds.size.height - outset;
	if(offset > 0.0f) {
		pixelBounds.size.height -= offset;
	}
	// Clip right
	offset = myPosition.x + pixelBounds.origin.x + pixelBounds.size.width - screenBounds.origin.x - screenBounds.size.width - outset;
	if(offset > 0.0f) {
		pixelBounds.size.width -= offset;
	}

	self.position = myPosition;
	self.bounds = pixelBounds;
	self.anchorPoint = CGPointMake(-pixelBounds.origin.x / pixelBounds.size.width,-pixelBounds.origin.y / pixelBounds.size.height);
	[self setNeedsDisplay];
}

- (void) addLineToXY: (RMXYPoint) point
{
//	NSLog(@"addLineToXY %f %f", point.x, point.y);
	
	NSValue* value = [NSValue value:&point withObjCType:@encode(RMXYPoint)];

	if (points == nil)
	{
		points = [[NSMutableArray alloc] initWithObjects:value, nil];
		origin = point;
	
		self.position = [[contents mercatorToScreenProjection] projectXYPoint: origin];
//		NSLog(@"screen position set to %f %f", self.position.x, self.position.y);
		path = CGPathCreateMutable();
		CGPathMoveToPoint(path, NULL, 0.0f, 0.0f);
	}
	else
	{
		[points addObject:value];
		
		point.x = point.x - origin.x;
		point.y = point.y - origin.y;
		
		CGPathAddLineToPoint(path, NULL, point.x, -point.y);
	
		// The bounds are actually in mercators...
		boundsInMercators = CGPathGetBoundingBox(path);

		[self recalculateGeometry];
	}
}

- (void) addLineToScreenPoint: (CGPoint) point
{
	RMXYPoint mercator = [[contents mercatorToScreenProjection] projectScreenPointToXY: point];
	
	[self addLineToXY: mercator];
}

- (void) addLineToLatLong: (RMLatLong) point
{
	RMXYPoint mercator = [[contents projection] latLongToPoint:point];
	
	[self addLineToXY:mercator];
}

- (void)drawInContext:(CGContextRef)theContext
{
	float scale, scaledLineWidth;
	
//	CGContextFillRect(theContext, self.bounds);//CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
	
	renderedScale = [contents scale];
	scale = 1.0f / renderedScale;

	scaledLineWidth = lineWidth;
	if(!scaleLineWidth) {
		scaledLineWidth *= renderedScale;
	}

	CGContextScaleCTM(theContext, scale, scale);
	
	CGContextBeginPath(theContext);
	CGContextAddPath(theContext, path);
	
	CGContextSetLineWidth(theContext, scaledLineWidth);
	CGContextSetStrokeColorWithColor(theContext, [lineColor CGColor]);
	CGContextSetFillColorWithColor(theContext, [fillColor CGColor]);
	CGContextDrawPath(theContext, drawingMode);
	CGContextClosePath(theContext);
}

- (void) closePath
{
	CGPathCloseSubpath(path);
}

- (float) lineWidth
{
	return lineWidth;
}

- (void) setLineWidth: (float) newLineWidth
{
	lineWidth = newLineWidth;
	[self recalculateGeometry];
}

- (CGPathDrawingMode) drawingMode
{
	return drawingMode;
}

- (void) setDrawingMode: (CGPathDrawingMode) newDrawingMode
{
	drawingMode = newDrawingMode;
	[self setNeedsDisplay];
}

- (UIColor *)lineColor
{
    return lineColor; 
}
- (void)setLineColor:(UIColor *)aLineColor
{
    if (lineColor != aLineColor) {
        [lineColor release];
        lineColor = [aLineColor retain];
		[self setNeedsDisplay];
    }
}

- (UIColor *)fillColor
{
    return fillColor; 
}
- (void)setFillColor:(UIColor *)aFillColor
{
    if (fillColor != aFillColor) {
        [fillColor release];
        fillColor = [aFillColor retain];
		[self setNeedsDisplay];
    }
}

- (BOOL)scaleLineWidth
{
	return scaleLineWidth;
}

- (void)setScaleLineWidth:(BOOL)newState
{
	scaleLineWidth = newState;
	[self recalculateGeometry];
}

- (void)moveBy: (CGSize) delta {
	[super moveBy:delta];

	[self recalculateGeometry];
}

- (void)zoomByFactor: (float) zoomFactor near:(CGPoint) pivot
{
	[super zoomByFactor:zoomFactor near:pivot];

	[self recalculateGeometry];
}

@end