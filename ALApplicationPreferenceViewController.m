#import "ALApplicationTableDataSource.h"

#import "ALApplicationList.h"
#import "ALValueCell.h"

#import <Preferences/Preferences.h>

#include <notify.h>

__attribute__((visibility("hidden")))
@interface ALApplicationPreferenceViewController : PSViewController<UITableViewDelegate> {
@private
	ALApplicationTableDataSource *_dataSource;
	UITableView *_tableView;
	NSString *_navigationTitle;
    NSArray *descriptors;
	id settingsDefaultValue;
	NSString *settingsPath;
	NSMutableDictionary *settings;
	NSString *settingsKeyPrefix;
	NSString *settingsChangeNotification;
	BOOL singleEnabledMode;
}

- (id)initForContentSize:(CGSize)size;

@property (nonatomic, retain) NSString *navigationTitle;
@property (nonatomic, readonly) UITableView *tableView;
@property (nonatomic, readonly) ALApplicationTableDataSource *dataSource;

- (void)cellAtIndexPath:(NSIndexPath *)indexPath didChangeToValue:(id)newValue;
- (id)valueForCellAtIndexPath:(NSIndexPath *)indexPath;

@end

__attribute__((visibility("hidden")))
@interface ALPreferencesTableDataSource : ALApplicationTableDataSource<ALValueCellDelegate> {
@private
	ALApplicationPreferenceViewController *_controller;
}

- (id)initWithController:(ALApplicationPreferenceViewController *)controller;

@end

@implementation ALPreferencesTableDataSource

- (id)initWithController:(ALApplicationPreferenceViewController *)controller
{
	if ((self = [super init])) {
		_controller = controller;
	}
	return self;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	id cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if ([cell isKindOfClass:[ALValueCell class]]) {
		[cell setDelegate:self];
		[cell loadValue:[_controller valueForCellAtIndexPath:indexPath]];
	}
	return cell;
}

- (void)valueCell:(ALValueCell *)valueCell didChangeToValue:(id)newValue
{
	[_controller cellAtIndexPath:[self.tableView indexPathForCell:valueCell] didChangeToValue:newValue];
}

@end

@interface PSViewController (OS32)
- (void)setSpecifier:(PSSpecifier *)specifier;
@end

@implementation ALApplicationPreferenceViewController

- (id)initForContentSize:(CGSize)size
{
	if ([[PSViewController class] instancesRespondToSelector:@selector(initForContentSize:)])
		self = [super initForContentSize:size];
	else
		self = [super init];
	if (self) {
		CGRect frame;
		frame.origin = CGPointZero;
		frame.size = size;
		_tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStyleGrouped];
		_dataSource = [[ALPreferencesTableDataSource alloc] initWithController:self];
		[_tableView setDataSource:_dataSource];
		[_tableView setDelegate:self];
		[_tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
		_dataSource.tableView = _tableView;
	}
	return self;
}

- (void)dealloc
{
	[_tableView setDelegate:nil];
	[_tableView setDataSource:nil];
	[_tableView release];
	_dataSource.tableView = nil;
	[_dataSource release];
	[settingsDefaultValue release];
	[settingsPath release];
	[settingsKeyPrefix release];
	[settingsChangeNotification release];
	[_navigationTitle release];
	[super dealloc];
}

@synthesize tableView = _tableView, dataSource = _dataSource, navigationTitle = _navigationTitle;

- (void)setNavigationTitle:(NSString *)navigationTitle
{
	[_navigationTitle autorelease];
	_navigationTitle = [navigationTitle retain];
	if ([self respondsToSelector:@selector(navigationItem)])
		[[self navigationItem] setTitle:_navigationTitle];
}

- (void)_updateSections
{
    NSInteger index = 0;
    for (NSDictionary *descriptor in descriptors) {
        NSString *predicateFormat = [descriptor objectForKey:ALSectionDescriptorVisibilityPredicateKey];
        if (!predicateFormat) {
        	index++;
        	continue;
        }
        NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateFormat];
        BOOL visible = [predicate evaluateWithObject:settings];
        NSArray *existingDescriptors = [_dataSource sectionDescriptors];
        BOOL already = [existingDescriptors count] > index ? [existingDescriptors objectAtIndex:index] == descriptor : NO;
        if (visible) {
            if (!already) {
                [_dataSource insertSectionDescriptor:descriptor atIndex:index];
            }
            index++;
        } else {
            if (already) {
                [_dataSource removeSectionDescriptorAtIndex:index];
            }
        }
    }
}

- (void)loadFromSpecifier:(PSSpecifier *)specifier
{
	[self setNavigationTitle:[specifier propertyForKey:@"ALNavigationTitle"] ?: [specifier name]];
	singleEnabledMode = [[specifier propertyForKey:@"ALSingleEnabledMode"] boolValue];

    [descriptors release];
	descriptors = [specifier propertyForKey:@"ALSectionDescriptors"];
	if (descriptors == nil) {
		NSString *defaultCellClass = singleEnabledMode ? @"ALCheckCell" : @"ALSwitchCell";
		NSNumber *iconSize = [NSNumber numberWithUnsignedInteger:ALApplicationIconSizeSmall];
		descriptors = [NSArray arrayWithObjects:
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"System Applications", ALSectionDescriptorTitleKey,
				@"isSystemApplication = TRUE", ALSectionDescriptorPredicateKey,
				defaultCellClass, ALSectionDescriptorCellClassNameKey,
				iconSize, ALSectionDescriptorIconSizeKey,
			nil],
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"User Applications", ALSectionDescriptorTitleKey,
				@"isSystemApplication = FALSE", ALSectionDescriptorPredicateKey,
				defaultCellClass, ALSectionDescriptorCellClassNameKey,
				iconSize, ALSectionDescriptorIconSizeKey,
			nil],
		nil];
	}
	[_dataSource setSectionDescriptors:descriptors];
    [descriptors retain];

	NSString *bundlePath = [specifier propertyForKey:@"ALLocalizationBundle"];
	_dataSource.localizationBundle = bundlePath ? [NSBundle bundleWithPath:bundlePath] : nil;

	[settingsDefaultValue release];
	settingsDefaultValue = [[specifier propertyForKey:@"ALSettingsDefaultValue"] retain];

	[settingsPath release];
	settingsPath = [[specifier propertyForKey:@"ALSettingsPath"] retain];

	[settingsKeyPrefix release];
	settingsKeyPrefix = [[specifier propertyForKey:singleEnabledMode ? @"ALSettingsKey" : @"ALSettingsKeyPrefix"] ?: @"ALValue-" retain];

	settings = [[NSMutableDictionary alloc] initWithContentsOfFile:settingsPath] ?: [[NSMutableDictionary alloc] init];

	[settingsChangeNotification release];
	settingsChangeNotification = [[specifier propertyForKey:@"ALChangeNotification"] retain];

	id temp = [specifier propertyForKey:@"ALAllowsSelection"];
	[_tableView setAllowsSelection:temp ? [temp boolValue] : singleEnabledMode];

    [self _updateSections];
	[_tableView reloadData];
}

- (void)setSpecifier:(PSSpecifier *)specifier
{
	[self loadFromSpecifier:specifier];
	[super setSpecifier:specifier];
}

- (void)viewWillBecomeVisible:(void *)source
{
	if (source)
		[self loadFromSpecifier:(PSSpecifier *)source];
	[super viewWillBecomeVisible:source];
}

- (UIView *)view
{
	return _tableView;
}

- (CGSize)contentSize
{
	return [_tableView frame].size;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	id cell = [_tableView cellForRowAtIndexPath:indexPath];
	if ([cell respondsToSelector:@selector(didSelect)])
		[cell didSelect];
	id cellDescriptor = [_dataSource cellDescriptorForIndexPath:indexPath];
	if ([cellDescriptor isKindOfClass:[NSDictionary class]]) {
		SEL action = NSSelectorFromString([[cellDescriptor objectForKey:@"action"] stringByAppendingString:@"FromCellDescriptor:"]);
		if ([self respondsToSelector:action])
			objc_msgSend(self, action, cellDescriptor);
	}
	[_tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)cellAtIndexPath:(NSIndexPath *)indexPath didChangeToValue:(id)newValue
{
	id cellDescriptor = [_dataSource cellDescriptorForIndexPath:indexPath];
	if ([cellDescriptor isKindOfClass:[NSDictionary class]]) {
		[settings setObject:newValue forKey:[cellDescriptor objectForKey:@"ALSettingsKey"]];
	} else if (singleEnabledMode) {
		if ([newValue boolValue]) {
			[settings setObject:cellDescriptor forKey:settingsKeyPrefix];
			for (NSIndexPath *otherIndexPath in [_tableView indexPathsForVisibleRows]) {
				if (![otherIndexPath isEqual:indexPath]) {
					ALValueCell *otherCell = (ALValueCell *)[_tableView cellForRowAtIndexPath:otherIndexPath];
					[otherCell loadValue:(id)kCFBooleanFalse];
				}
			}
		} else if ([[settings objectForKey:settingsKeyPrefix] isEqual:cellDescriptor]) {
			[settings removeObjectForKey:settingsKeyPrefix];
		}
	} else {
		NSString *key = [settingsKeyPrefix stringByAppendingString:cellDescriptor];
		[settings setObject:newValue forKey:key];
	}
	if (settingsPath)
		[settings writeToFile:settingsPath atomically:YES];
	if (settingsChangeNotification)
		notify_post([settingsChangeNotification UTF8String]);
    [self _updateSections];
}

- (id)valueForCellAtIndexPath:(NSIndexPath *)indexPath
{
	id cellDescriptor = [_dataSource cellDescriptorForIndexPath:indexPath];
	if ([cellDescriptor isKindOfClass:[NSDictionary class]]) {
		return [settings objectForKey:[cellDescriptor objectForKey:@"ALSettingsKey"]] ?: [cellDescriptor objectForKey:@"ALSettingsDefaultValue"];
	}
	if (singleEnabledMode) {
		return [[settings objectForKey:settingsKeyPrefix] isEqualToString:cellDescriptor] ? (id)kCFBooleanTrue : (id)kCFBooleanFalse;
	} else {
		NSString *key = [settingsKeyPrefix stringByAppendingString:cellDescriptor];
		return [settings objectForKey:key] ?: settingsDefaultValue;
	}
}

- (void)pushController:(id<PSBaseView>)controller
{
	[super pushController:controller];
	[controller setParentController:self];
}

- (void)launchURLFromCellDescriptor:(NSDictionary *)cellDescriptor
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[cellDescriptor objectForKey:@"url"]]];
}

@end
