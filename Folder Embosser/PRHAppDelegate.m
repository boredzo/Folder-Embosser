#import "PRHAppDelegate.h"
#import "PRHEmbosserWindowController.h"

@implementation PRHAppDelegate
{
	PRHEmbosserWindowController *_windowController;
}

- (void) applicationWillFinishLaunching:(NSNotification *)notification {
	_windowController = [[PRHEmbosserWindowController alloc] init];
	[_windowController showWindow:nil];
}

- (void) applicationWillTerminate:(NSNotification *)notification {
	[_windowController close];
	_windowController = nil;
}

- (void) application:(NSApplication *)sender openFiles:(NSArray *)filenames {
	if (filenames.count > 0) {
		[_windowController loadTemplateImageFromFile:filenames[0]];
	}
}


@end
