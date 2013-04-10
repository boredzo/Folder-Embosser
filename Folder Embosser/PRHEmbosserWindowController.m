#import "PRHEmbosserWindowController.h"

@interface PRHEmbosserWindowController ()

@property (weak) IBOutlet NSImageView *templateImageView;
@property (weak) IBOutlet NSImageView *folderImageView;
@property (weak) IBOutlet NSImageView *outputImageView;

@property (copy) NSImage *templateImage;
@property (nonatomic, readonly) NSImage *outputImage;

@end

@implementation PRHEmbosserWindowController
{
	NSImage *_folderImage;
}

- (id) initWithWindow:(NSWindow *)window {
	if ((self = [super initWithWindow:window])) {
		_folderImage = [NSImage imageNamed:NSImageNameFolder];
		_folderImage.size = (NSSize){ 128.0, 128.0 };
	}
	return self;
}

- (id) init {
	return [self initWithWindowNibName:NSStringFromClass([self class])];
}

- (CIFilter *) filterByLoadingOrCreatingIt {
	CIFilterGenerator *generator = [self filterGeneratorByLoadingIt];
	if (!generator) {
		generator = [self filterGeneratorByCreatingIt];
	}

	return [generator filter];
}

- (NSURL *) filterURL {
	NSFileManager *manager = [[NSFileManager alloc] init];
	NSError *error = nil;
	NSURL *cachesDirURL = [manager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
	       appropriateForURL:nil create:YES error:&error];
	NSURL *ourCacheURL = [cachesDirURL URLByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier isDirectory:YES];
	[manager createDirectoryAtURL:ourCacheURL withIntermediateDirectories:NO
		attributes:nil error:&error];
	NSURL *filterURL = [ourCacheURL URLByAppendingPathComponent:@"emboss.cifilter" isDirectory:NO];
	return filterURL;
}

- (CIFilterGenerator *) filterGeneratorByLoadingIt {
	NSURL *filterURL = [self filterURL];
	NSError *error_nobodyCares = nil;
	bool exists = [filterURL checkResourceIsReachableAndReturnError:&error_nobodyCares];
	CIFilterGenerator *generator = exists ? [CIFilterGenerator filterGeneratorWithContentsOfURL:filterURL] : nil;
	return generator;
}

- (CIFilterGenerator *) filterGeneratorByCreatingIt {
	CIFilterGenerator *generator = [CIFilterGenerator filterGenerator];

	CIFilter *alphaToMask = [self singleFilterWithName:@"CIColorMatrix" withValues:@{
		@"inputRVector": [CIVector vectorWithX:1.0 Y:0.0 Z:0.0 W:1.0],
		@"inputGVector": [CIVector vectorWithX:0.0 Y:1.0 Z:0.0 W:1.0],
		@"inputBVector": [CIVector vectorWithX:0.0 Y:0.0 Z:1.0 W:1.0],
	}];
	CIFilter *edgeWork = [self singleFilterWithName:@"CIEdgeWork" withValues:@{
		kCIInputRadiusKey: @0.5,
	}];
	CIVector *allBalls = [CIVector vectorWithX:0.0 Y:0.0 Z:0.0 W:0.0];
	CIFilter *whiteToBlack = [self singleFilterWithName:@"CIColorMatrix" withValues:@{
		@"inputRVector": allBalls,
		@"inputGVector": allBalls,
		@"inputBVector": allBalls,
	}];
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform translateXBy:0.0 yBy:+1.0];
	CIFilter *nudgeUpward = [CIFilter filterWithName:@"CIAffineTransform" keysAndValues:
		kCIInputTransformKey, transform,
		nil];
	[generator connectObject:alphaToMask withKey:kCIOutputImageKey
	                toObject:edgeWork withKey:kCIInputImageKey];
	[generator connectObject:edgeWork withKey:kCIOutputImageKey
	                toObject:whiteToBlack withKey:kCIInputImageKey];
	[generator connectObject:whiteToBlack withKey:kCIOutputImageKey
	                toObject:nudgeUpward withKey:kCIInputImageKey];

	CIFilter *oneHalfAlpha = [self singleFilterWithName:@"CIColorMatrix" withValues:@{
		@"inputAVector": [CIVector vectorWithX:0.0 Y:0.0 Z:0.0 W:0.5],
	}];

	CIFilter *oneHalfOverEdges = [CIFilter filterWithName:@"CISourceOverCompositing"];
	[generator connectObject:oneHalfAlpha withKey:kCIOutputImageKey
	                toObject:oneHalfOverEdges withKey:kCIInputImageKey];
	[generator connectObject:nudgeUpward withKey:kCIOutputImageKey
	                toObject:oneHalfOverEdges withKey:kCIInputBackgroundImageKey];

	CIFilter *oneFifthAlpha = [self singleFilterWithName:@"CIColorMatrix" withValues:@{
		@"inputAVector": [CIVector vectorWithX:0.0 Y:0.0 Z:0.0 W:0.2],
	}];
	[generator connectObject:oneHalfOverEdges withKey:kCIOutputImageKey
	                toObject:oneFifthAlpha withKey:kCIInputImageKey];

	CIFilter *multiplyEdgedTemplateOverFolder = [CIFilter filterWithName:@"CIMultiplyBlendMode"];
	[generator connectObject:oneFifthAlpha withKey:kCIOutputImageKey
	                toObject:multiplyEdgedTemplateOverFolder withKey:kCIInputImageKey];

	[generator exportKey:kCIInputImageKey fromObject:alphaToMask withName:nil];
	[generator exportKey:kCIInputImageKey fromObject:oneHalfAlpha withName:nil];
	[generator exportKey:kCIInputBackgroundImageKey fromObject:multiplyEdgedTemplateOverFolder withName:nil];
	[generator exportKey:kCIOutputImageKey fromObject:multiplyEdgedTemplateOverFolder withName:nil];

	return generator;
}

//Because filterWithName:keysAndValues: doesn't set default values.
- (CIFilter *) singleFilterWithName:(NSString *)filterName withValues:(NSDictionary *)values {
	CIFilter *filter = [CIFilter filterWithName:filterName];
	[filter setDefaults];
	[filter setValuesForKeysWithDictionary:values];
	return filter;
}

- (void) windowDidLoad {
	[super windowDidLoad];
}

+ (NSSet *) keyPathsForValuesAffectingOutputImage {
	return [NSSet setWithArray:@[ @"folderImage", @"templateImage" ]];
}
- (NSImage *) outputImage {
	if (self.templateImage == nil) {
		return _folderImage;
	}

	CIFilter *filter = [self filterByLoadingOrCreatingIt];
	CIImage *sourceImage = [self CIImageWithNSImage:self.templateImage];
	[filter setValue:sourceImage forKey:kCIInputImageKey];
	CIImage *folderImage = [self CIImageWithNSImage:_folderImage];
	[filter setValue:folderImage forKey:kCIInputBackgroundImageKey];
	CIImage *embossedImage = [filter valueForKey:kCIOutputImageKey];
	NSImage *outputImage = [self NSImageWithCIImage:embossedImage];

#if DEBUG_WRITE_TIFFS
	NSFileManager *manager = [[NSFileManager alloc] init];
	NSError *error = nil;
	NSURL *URL = [manager
		URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask
	  appropriateForURL:nil create:YES error:&error];
	URL = [URL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier] isDirectory:YES];
	[manager createDirectoryAtURL:URL withIntermediateDirectories:NO
		attributes:nil error:&error];
	URL = [URL URLByAppendingPathComponent:@"output.tiff" isDirectory:NO];
	[[outputImage TIFFRepresentation]
		writeToURL:URL options:NSDataWritingAtomic error:&error];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ URL ]];
#endif

	return outputImage;
}

- (CIImage *) CIImageWithNSImage:(NSImage *)image {
	CGImageRef CGImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
	return [CIImage imageWithCGImage:CGImage];
}

- (NSImage *) NSImageWithCIImage:(CIImage *)image {
	CGRect extent = image.extent;
	size_t width = (size_t)extent.size.width;
	size_t height = (size_t)extent.size.height;
	CGColorSpaceRef colorSpace = image.colorSpace;
	id stronglyReferencedColorSpace;
	if (!colorSpace) {
		stronglyReferencedColorSpace = (__bridge_transfer id)CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		colorSpace = (__bridge CGColorSpaceRef)stronglyReferencedColorSpace;
	}
	size_t componentsPerPixel = 4;
	size_t bytesPerComponent = 1;
	size_t bytesPerRow = width * componentsPerPixel * bytesPerComponent;
	CGContextRef cgContext = CGBitmapContextCreate(NULL, width, height,
		8 * bytesPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
	CIContext *context = [CIContext contextWithCGContext:cgContext options:@{ kCIContextWorkingColorSpace: (__bridge id)colorSpace }];

	id strongImage = (__bridge_transfer id)[context createCGImage:image fromRect:extent];
	CGImageRef CGImage = (__bridge CGImageRef)strongImage;

	CGContextRelease(cgContext);

	return [[NSImage alloc] initWithCGImage:CGImage size:extent.size];
}

- (void) loadTemplateImageFromFile:(NSString *)path {
	self.templateImage = [[NSImage alloc] initWithContentsOfFile:path];
}

@end
