/*
 * Created by Mayur Pawashe on 8/9/13.
 *
 * Copyright (c) 2013 zgcoder
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ZGDocumentWindowController.h"
#import "ZGDocumentTableController.h"
#import "ZGDocumentSearchController.h"
#import "ZGVariableController.h"
#import "ZGEditValueWindowController.h"
#import "ZGEditAddressWindowController.h"
#import "ZGEditDescriptionWindowController.h"
#import "ZGEditSizeWindowController.h"
#import "ZGScriptManager.h"
#import "ZGProcessList.h"
#import "ZGProcess.h"
#import "ZGVariableTypes.h"
#import "ZGRunningProcess.h"
#import "ZGPreferencesController.h"
#import "ZGDocumentData.h"
#import "ZGSearchData.h"
#import "ZGSearchProgress.h"
#import "ZGSearchResults.h"
#import "ZGDebuggerController.h"
#import "ZGBreakPointController.h"
#import "ZGMemoryViewerController.h"
#import "ZGDocument.h"
#import "ZGVirtualMemory.h"
#import "ZGMachBinary.h"
#import "ZGMachBinaryInfo.h"
#import "APTokenSearchField.h"
#import "ZGSearchToken.h"
#import "ZGDocumentOptionsViewController.h"
#import "ZGWatchVariableWindowController.h"
#import "ZGUtilities.h"
#import "ZGTableView.h"
#import "ZGNavigationPost.h"

#define ZGProtectionGroup @"ZGProtectionGroup"
#define ZGProtectionItemAll @"ZGProtectionAll"
#define ZGProtectionItemWrite @"ZGProtectionWrite"
#define ZGProtectionItemExecute @"ZGProtectionExecute"

#define ZGQualifierGroup @"ZGQualifierGroup"
#define ZGQualifierSigned @"ZGQualifierSigned"
#define ZGQualifierUnsigned @"ZGQualifierUnsigned"

#define ZGStringMatchingGroup @"ZGStringMatchingGroup"
#define ZGStringIgnoreCase @"ZGStringIgnoreCase"
#define ZGStringNullTerminated @"ZGStringNullTerminated"

#define ZGEndianGroup @"ZGEndianGroup"
#define ZGEndianLittle @"ZGEndianLittle"
#define ZGEndianBig @"ZGEndianBig"

@interface ZGDocumentWindowController ()

@property (nonatomic, copy) NSString *lastChosenInternalProcessName;

@property (nonatomic) NSString *flagsStringValue;
@property (nonatomic) NSString *flagsLabelStringValue;

@property (nonatomic) ZGProcessList *processList;
@property (nonatomic) ZGProcessTaskManager *processTaskManager;
@property (nonatomic) ZGDebuggerController *debuggerController;
@property (nonatomic) ZGBreakPointController *breakPointController;
@property (nonatomic) ZGMemoryViewerController *memoryViewer;
@property (nonatomic) ZGLoggerWindowController *loggerWindowController;

@property (nonatomic) ZGWatchVariableWindowController *watchVariableWindowController;

@property (nonatomic) ZGEditValueWindowController *editValueWindowController;
@property (nonatomic) ZGEditAddressWindowController *editAddressWindowController;
@property (nonatomic) ZGEditDescriptionWindowController *editDescriptionWindowController;
@property (nonatomic) ZGEditSizeWindowController *editSizeWindowController;

@property (nonatomic, assign) IBOutlet AGScopeBar *scopeBar;
@property (nonatomic, assign) IBOutlet NSView *scopeBarFlagsView;

@property (nonatomic) AGScopeBarGroup *protectionGroup;
@property (nonatomic) AGScopeBarGroup *qualifierGroup;
@property (nonatomic) AGScopeBarGroup *stringMatchingGroup;
@property (nonatomic) AGScopeBarGroup *endianGroup;

@property (nonatomic, assign) IBOutlet NSTextField *generalStatusTextField;
@property (nonatomic, assign) IBOutlet NSTextField *flagsTextField;
@property (nonatomic, assign) IBOutlet NSTextField *flagsLabel;

@property (nonatomic) NSPopover *advancedOptionsPopover;

@end

@implementation ZGDocumentWindowController

- (id)initWithDocument:(ZGDocument *)document
{
	self = [super initWithWindowNibName:@"MyDocument"];
	if (self != nil)
	{
		// Still need to observe this for reliably fetching icon and localized name
		[[NSWorkspace sharedWorkspace]
		 addObserver:self
		 forKeyPath:@"runningApplications"
		 options:NSKeyValueObservingOptionNew
		 context:NULL];
		
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(lastChosenInternalProcessNameChanged:)
		 name:ZGLastChosenInternalProcessNameNotification
		 object:nil];
		
		self.lastChosenInternalProcessName = document.lastChosenInternalProcessName;
		
		self.processTaskManager = document.processTaskManager;
		self.debuggerController = document.debuggerController;
		self.breakPointController = document.breakPointController;
		self.loggerWindowController = document.loggerWindowController;
		
		self.processList = [[ZGProcessList alloc] initWithProcessTaskManager:self.processTaskManager];
		
		[self.processList
		 addObserver:self
		 forKeyPath:@"runningProcesses"
		 options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
		 context:NULL];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	
	[self.processList
	 removeObserver:self
	 forKeyPath:@"runningProcesses"];
	
	[[NSWorkspace sharedWorkspace]
	 removeObserver:self
	 forKeyPath:@"runningApplications"];
}

- (void)setupScopeBar
{
	self.protectionGroup = [self.scopeBar addGroupWithIdentifier:ZGProtectionGroup label:@"Protection:" items:nil];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemAll title:@"All"];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemWrite title:@"Write"];
	[self.protectionGroup addItemWithIdentifier:ZGProtectionItemExecute title:@"Execute"];
	self.protectionGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	self.qualifierGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGQualifierGroup];
	self.qualifierGroup.label = @"Qualifier:";
	[self.qualifierGroup addItemWithIdentifier:ZGQualifierSigned title:@"Signed"];
	[self.qualifierGroup addItemWithIdentifier:ZGQualifierUnsigned title:@"Unsigned"];
	self.qualifierGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	self.stringMatchingGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGStringMatchingGroup];
	self.stringMatchingGroup.label = @"Matching:";
	[self.stringMatchingGroup addItemWithIdentifier:ZGStringIgnoreCase title:@"Ignore Case"];
	[self.stringMatchingGroup addItemWithIdentifier:ZGStringNullTerminated title:@"Null Terminated"];
	self.stringMatchingGroup.selectionMode = AGScopeBarGroupSelectAny;
	
	self.endianGroup = [[AGScopeBarGroup alloc] initWithIdentifier:ZGEndianGroup];
	self.endianGroup.label = @"Endianness";
	[self.endianGroup addItemWithIdentifier:ZGEndianLittle title:@"Little"];
	[self.endianGroup addItemWithIdentifier:ZGEndianBig title:@"Big"];
	self.endianGroup.selectionMode = AGScopeBarGroupSelectOne;
	
	// Set delegate after setting up scope bar so we won't receive initial selection events beforehand
	self.scopeBar.delegate = self;
}

- (void)scopeBar:(AGScopeBar *)__unused scopeBar item:(AGScopeBarItem *)item wasSelected:(BOOL)selected
{
	if ([item.group.identifier isEqualToString:ZGProtectionGroup])
	{
		if (selected)
		{
			if ([item.identifier isEqualToString:ZGProtectionItemAll])
			{
				self.searchData.protectionMode = ZGProtectionAll;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemWrite])
			{
				self.searchData.protectionMode = ZGProtectionWrite;
			}
			else if ([item.identifier isEqualToString:ZGProtectionItemExecute])
			{
				self.searchData.protectionMode = ZGProtectionExecute;
			}
			
			[self markDocumentChange];
		}
	}
	else if ([item.group.identifier isEqualToString:ZGQualifierGroup])
	{
		if (selected)
		{
			[self changeIntegerQualifier:[item.identifier isEqualToString:ZGQualifierSigned] ? ZGSigned : ZGUnsigned];
		}
	}
	else if ([item.group.identifier isEqualToString:ZGStringMatchingGroup])
	{
		if ([item.identifier isEqualToString:ZGStringIgnoreCase])
		{
			self.searchData.shouldIgnoreStringCase = selected;
		}
		else if ([item.identifier isEqualToString:ZGStringNullTerminated])
		{
			self.searchData.shouldIncludeNullTerminator = selected;
		}
		
		[self markDocumentChange];
	}
	else if ([item.group.identifier isEqualToString:ZGEndianGroup])
	{
		CFByteOrder newByteOrder = [item.identifier isEqualToString:ZGEndianLittle] ? CFByteOrderLittleEndian : CFByteOrderBigEndian;
		
		if (newByteOrder != self.documentData.byteOrderTag)
		{
			self.documentData.byteOrderTag = newByteOrder;
			
			for (ZGVariable *variable in self.documentData.variables)
			{
				variable.byteOrder = newByteOrder;
				switch (variable.type)
				{
					case ZGInt16:
					case ZGInt32:
					case ZGInt64:
					case ZGFloat:
					case ZGDouble:
					case ZGPointer:
					case ZGString16:
						[variable updateStringValue];
						break;
					case ZGInt8:
					case ZGByteArray:
					case ZGString8:
					case ZGScript:
						break;
				}
			}
			
			[self.variablesTableView reloadData];
			[self markDocumentChange];
		}
	}
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	self.documentData = [(ZGDocument *)self.document data];
	self.searchData = [self.document searchData];
	
	self.tableController = [[ZGDocumentTableController alloc] initWithWindowController:self];
	self.variableController = [[ZGVariableController alloc] initWithWindowController:self];
	self.searchController = [[ZGDocumentSearchController alloc] initWithWindowController:self];
	self.scriptManager = [[ZGScriptManager alloc] initWithWindowController:self];
	
	self.tableController.variablesTableView = self.variablesTableView;
	
	self.searchValueTextField.cell.sendsSearchStringImmediately = NO;
	self.searchValueTextField.cell.sendsSearchStringOnlyAfterReturn = YES;
	
	[self setupScopeBar];
	
	[self.storeValuesButton.image setTemplate:YES];
	[[NSImage imageNamed:@"container_filled"] setTemplate:YES];
	
	[self.generalStatusTextField.cell setBackgroundStyle:NSBackgroundStyleRaised];
	
	if ([self.window respondsToSelector:@selector(occlusionState)])
	{
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(windowDidChangeOcclusionState:)
		 name:NSWindowDidChangeOcclusionStateNotification
		 object:self.window];
	}
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(runningApplicationsPopUpButtonWillPopUp:)
	 name:NSPopUpButtonWillPopUpNotification
	 object:self.runningApplicationsPopUpButton];
	
	[self loadDocumentUserInterface];
}

- (void)updateObservingProcessOcclusionState
{
	if ([self.window respondsToSelector:@selector(occlusionState)])
	{
		BOOL shouldKeepWatchVariablesTimer = [self.tableController updateWatchVariablesTimer];
		if (self.isOccluded && !shouldKeepWatchVariablesTimer && !self.searchController.canCancelTask)
		{
			BOOL foundRunningScript = NO;
			for (ZGVariable *variable in self.documentData.variables)
			{
				if (variable.enabled && variable.type == ZGScript)
				{
					foundRunningScript = YES;
					break;
				}
			}
			
			if (!foundRunningScript)
			{
				if (self.currentProcess.valid)
				{
					[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
				}
				
				[self.processList unrequestPollingWithObserver:self];
			}
		}
		else if (!self.isOccluded)
		{
			if (self.currentProcess.valid)
			{
				[self.processList addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
			}
			else
			{
				[self.processList requestPollingWithObserver:self];
			}
		}
	}
}

- (void)windowDidChangeOcclusionState:(NSNotification *)__unused notification
{
	self.isOccluded = (self.window.occlusionState & NSWindowOcclusionStateVisible) == 0;
	if (!self.isOccluded)
	{
		[self.processList retrieveList];
		[self.tableController.variablesTableView reloadData];
	}
	[self updateObservingProcessOcclusionState];
}

- (void)windowWillClose:(NSNotification *)notification
{
	if ([notification object] == self.window)
	{
		if (self.currentProcess.valid)
		{
			[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		}
		
		[self.processList unrequestPollingWithObserver:self];

		[self.searchController cleanUp];
		[self.tableController cleanUp];
		[self.scriptManager cleanup];
	}
}

- (void)setStatus:(id)status
{
	if (status == nil)
	{
		NSUInteger variableCount = self.documentData.variables.count + self.searchController.searchResults.addressCount;
		
		NSNumberFormatter *numberOfVariablesFormatter = [[NSNumberFormatter alloc] init];
		numberOfVariablesFormatter.format = @"#,###";
		
		NSString *valuesDisplayedString = [NSString stringWithFormat:@"Displaying %@ value", [numberOfVariablesFormatter stringFromNumber:@(variableCount)]];
		
		if (variableCount != 1)
		{
			valuesDisplayedString = [valuesDisplayedString stringByAppendingString:@"s"];
		}
		
		[self.generalStatusTextField setStringValue:valuesDisplayedString];
	}
	else if ([status isKindOfClass:[NSString class]])
	{
		[self.generalStatusTextField setStringValue:status];
	}
	else if ([status isKindOfClass:[NSAttributedString class]])
	{
		[self.generalStatusTextField setAttributedStringValue:status];
	}
}

- (void)loadDocumentUserInterface
{
	[self setStatus:nil];
	
	[self addProcessesToPopupButton];
	
	[self.variableController disableHarmfulVariables:self.documentData.variables];
	[self updateVariables:self.documentData.variables searchResults:nil];
	
	switch (self.searchData.protectionMode)
	{
		case ZGProtectionAll:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemAll];
			break;
		case ZGProtectionWrite:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemWrite];
			break;
		case ZGProtectionExecute:
			[self.protectionGroup setSelected:YES forItemWithIdentifier:ZGProtectionItemExecute];
			break;
	}
	
	if (self.documentData.qualifierTag == ZGSigned)
	{
		[self.qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierSigned];
	}
	else
	{
		[self.qualifierGroup setSelected:YES forItemWithIdentifier:ZGQualifierUnsigned];
	}
	
	if (self.searchData.shouldIgnoreStringCase)
	{
		[self.stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringIgnoreCase];
	}
	
	if (self.searchData.shouldIncludeNullTerminator)
	{
		[self.stringMatchingGroup setSelected:YES forItemWithIdentifier:ZGStringNullTerminated];
	}
	
	[self.endianGroup setSelected:YES forItemWithIdentifier:self.documentData.byteOrderTag == CFByteOrderBigEndian ? ZGEndianBig : ZGEndianLittle];
	
	if (self.advancedOptionsPopover != nil)
	{
		ZGDocumentOptionsViewController *optionsViewController = (id)self.advancedOptionsPopover.contentViewController;
		[optionsViewController reloadInterface];
	}
	
	self.searchValueTextField.objectValue = self.documentData.searchValue;
	[self.window makeFirstResponder:self.searchValueTextField];
	
	[self.dataTypesPopUpButton selectItemWithTag:self.documentData.selectedDatatypeTag];
	[self selectDataTypeWithTag:(ZGVariableType)self.documentData.selectedDatatypeTag recordUndo:NO];
	
	[self.functionPopUpButton selectItemWithTag:self.documentData.functionTypeTag];
	[self updateOptions];
	
	[self.scriptManager loadCachedScriptsFromVariables:self.documentData.variables];
}

#pragma mark Selected Variables

- (NSIndexSet *)selectedVariableIndexes
{
	NSIndexSet *tableIndexSet = self.tableController.variablesTableView.selectedRowIndexes;
	NSInteger clickedRow = self.tableController.variablesTableView.clickedRow;
	
	return (clickedRow >= 0 && ![tableIndexSet containsIndex:(NSUInteger)clickedRow]) ? [NSIndexSet indexSetWithIndex:(NSUInteger)clickedRow] : tableIndexSet;
}

- (NSArray *)selectedVariables
{
	return [self.documentData.variables objectsAtIndexes:[self selectedVariableIndexes]];
}

#pragma mark Undo Manager

- (NSUndoManager *)windowWillReturnUndoManager:(id)__unused sender
{
	return [(ZGDocument *)self.document undoManager];
}

- (id)undoManager
{
	return [(ZGDocument *)self.document undoManager];
}

- (void)markDocumentChange
{
	[self.document markChange];
}

- (IBAction)undoDocument:(id)__unused sender
{
	[self.undoManager undo];
}

- (IBAction)redoDocument:(id)__unused sender
{
	[self.undoManager redo];
}

#pragma mark Watching other applications

- (void)lastChosenInternalProcessNameChanged:(NSNotification *)notification
{
	if (notification.object != self)
	{
		self.lastChosenInternalProcessName = [notification.userInfo objectForKey:ZGLastChosenInternalProcessNameKey];
	}
}

- (void)postLastChosenInternalProcessNameChange
{
	[[NSNotificationCenter defaultCenter]
	 postNotificationName:ZGLastChosenInternalProcessNameNotification
	 object:self
	 userInfo:@{ZGLastChosenInternalProcessNameKey : self.lastChosenInternalProcessName}];
}

- (void)runningApplicationsPopUpButtonWillPopUp:(NSNotification *)__unused notification
{
	[self.processList retrieveList];
}

- (IBAction)runningApplicationsPopUpButtonRequest:(id)sender
{
	BOOL pointerSizeChanged = YES;
	
	if (self.runningApplicationsPopUpButton.selectedItem.representedObject != self.currentProcess)
	{
		if (self.runningApplicationsPopUpButton.selectedItem.representedObject && self.currentProcess && [self.runningApplicationsPopUpButton.selectedItem.representedObject is64Bit] != self.currentProcess.is64Bit)
		{
			pointerSizeChanged = YES;
		}
		
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (variable.enabled)
			{
				if (variable.type == ZGScript)
				{
					[self.scriptManager stopScriptForVariable:variable];
				}
				else if (variable.isFrozen)
				{
					variable.enabled = NO;
				}
			}
			
			variable.finishedEvaluatingDynamicAddress = NO;
		}
		
		// this is about as far as we go when it comes to undo/redos...
		[self.undoManager removeAllActions];
		
		[self.tableController clearCache];
	}
	
	if (self.currentProcess)
	{
		[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
	}
	
	self.currentProcess = self.runningApplicationsPopUpButton.selectedItem.representedObject;
	
	if (pointerSizeChanged)
	{
		// Update the pointer variable sizes
		for (ZGVariable *variable in self.documentData.variables)
		{
			if (variable.type == ZGPointer)
			{
				variable.pointerSize = self.currentProcess.pointerSize;
			}
		}
		
		[self.tableController.variablesTableView reloadData];
	}
	
	// keep track of the process the user targeted
	if (self.currentProcess.internalName != nil)
	{
		self.lastChosenInternalProcessName = self.currentProcess.internalName;
		[self postLastChosenInternalProcessNameChange];
	}
	
	if (sender != nil && ![self.documentData.desiredProcessInternalName isEqualToString:self.currentProcess.internalName])
	{
		self.documentData.desiredProcessInternalName = self.currentProcess.internalName;
		[self markDocumentChange];
	}
	else if (self.documentData.desiredProcessInternalName == nil)
	{
		self.documentData.desiredProcessInternalName = self.currentProcess.internalName;
	}
	
	if (self.currentProcess && self.currentProcess.valid)
	{
		[self.processList addPriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
		
		if (!self.currentProcess.hasGrantedAccess && !ZGGrantMemoryAccessToProcess(self.processTaskManager, self.currentProcess))
		{
			[self setStatus:[NSString stringWithFormat:@"Failed accessing %@", self.currentProcess.name]];
		}
		else
		{
			[self setStatus:nil];
			
			self.storeValuesButton.enabled = YES;
		}
	}
	
	[self.tableController updateWatchVariablesTimer];
	
	// Trash all other menu items if they're dead
	NSMutableArray *itemsToRemove = [[NSMutableArray alloc] init];
	for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
	{
		ZGRunningProcess *runningProcess = [[ZGRunningProcess alloc] initWithProcessIdentifier:[[menuItem representedObject] processID]];
		if (menuItem != self.runningApplicationsPopUpButton.selectedItem &&
			(![menuItem.representedObject valid] ||
			 ![[self.processList runningProcesses] containsObject:runningProcess]))
		{
			[itemsToRemove addObject:menuItem];
		}
	}
	
	for (id item in itemsToRemove)
	{
		[self.runningApplicationsPopUpButton removeItemAtIndex:[self.runningApplicationsPopUpButton indexOfItem:item]];
	}
}

- (void)addProcessesToPopupButton
{
	NSString *lastSelectedProcessInternalName = self.lastChosenInternalProcessName;
	BOOL foundLastSelectedProcessInternalName = NO;
	
	// Add running applications to popup button; we want activiation policy for NSApplicationActivationPolicyRegular to appear first, since they're more likely to be targetted and more likely to have sufficient privillages for accessing virtual memory
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"activationPolicy" ascending:YES];
	for (ZGRunningProcess *runningProcess in [[self.processList runningProcesses] sortedArrayUsingDescriptors:@[sortDescriptor]])
	{
		// If there's no desired process, try to use the last selected process only if it exists
		if (self.documentData.desiredProcessInternalName == nil && lastSelectedProcessInternalName != nil && !foundLastSelectedProcessInternalName && [runningProcess.internalName isEqualToString:lastSelectedProcessInternalName])
		{
			self.documentData.desiredProcessInternalName = lastSelectedProcessInternalName;
			foundLastSelectedProcessInternalName = YES;
		}
		[self addRunningProcessToPopupButton:runningProcess];
	}
	
	if (self.documentData.desiredProcessInternalName != nil && ![self.currentProcess.internalName isEqualToString:self.documentData.desiredProcessInternalName])
	{
		ZGProcess *deadProcess = [[ZGProcess alloc] initWithName:nil internalName:self.documentData.desiredProcessInternalName is64Bit:YES];
		
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		menuItem.title = [NSString stringWithFormat:@"%@ (none)", deadProcess.internalName];
		menuItem.representedObject = deadProcess;
		
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		
		[self.runningApplicationsPopUpButton selectItem:menuItem];
		
		[self runningApplicationsPopUpButtonRequest:nil];
		[self removeRunningProcessFromPopupButton:nil];
	}
	else
	{
		[self runningApplicationsPopUpButtonRequest:nil];
	}
}

- (void)removeRunningProcessFromPopupButton:(ZGRunningProcess *)oldRunningProcess
{
	// Just to be sure
	if (oldRunningProcess.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
	{
		// oldRunningProcess == nil, means remove 'current process'
		if (self.currentProcess.processID == oldRunningProcess.processIdentifier || !oldRunningProcess)
		{
			// Don't remove the item, just indicate it's terminated
			[self setStatus:[NSString stringWithFormat:@"%@ is not running", self.currentProcess.name]];
			
			if (self.searchController.canCancelTask && !self.searchController.searchProgress.shouldCancelSearch)
			{
				[self.searchController cancelTask];
			}
			
			[self.processList removePriorityToProcessIdentifier:self.currentProcess.processID withObserver:self];
			
			[self.tableController clearCache];
			for (ZGVariable *variable in self.documentData.variables)
			{
				variable.finishedEvaluatingDynamicAddress = NO;
				variable.value = NULL;
			}
			
			[self.currentProcess markInvalid];
			[self.tableController updateWatchVariablesTimer];
			[self.variablesTableView reloadData];
			
			self.storeValuesButton.enabled = NO;
			
			[[NSNotificationCenter defaultCenter]
			 postNotificationName:ZGTargetProcessDiedNotification
			 object:self.currentProcess];
			
			ZGUpdateProcessMenuItem(self.runningApplicationsPopUpButton.selectedItem, self.currentProcess.internalName, -1, nil);
			
			[self.processList requestPollingWithObserver:self];
		}
		else if (oldRunningProcess.processIdentifier != -1)
		{
			// Find the menu item, and remove it
			NSMenuItem *itemToRemove = nil;
			for (NSMenuItem *item in self.runningApplicationsPopUpButton.itemArray)
			{
				if ([item.representedObject processID] == oldRunningProcess.processIdentifier)
				{
					itemToRemove = item;
					break;
				}
			}
			
			if (itemToRemove)
			{
				[self.runningApplicationsPopUpButton removeItemAtIndex:[self.runningApplicationsPopUpButton indexOfItem:itemToRemove]];
			}
		}
	}
}

- (void)addRunningProcessToPopupButton:(ZGRunningProcess *)newRunningProcess
{
	// Don't add ourselves
	if (newRunningProcess.processIdentifier != NSRunningApplication.currentApplication.processIdentifier)
	{
		// Check if a dead application can be 'revived'
		for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
		{
			ZGProcess *process = menuItem.representedObject;
			if (process == self.currentProcess &&
				!self.currentProcess.valid &&
				[self.currentProcess.internalName isEqualToString:newRunningProcess.internalName])
			{
				self.currentProcess.processID = newRunningProcess.processIdentifier;
				self.currentProcess.name = newRunningProcess.name;
				self.currentProcess.is64Bit = newRunningProcess.is64Bit;
				
				ZGUpdateProcessMenuItem(menuItem, newRunningProcess.name, newRunningProcess.processIdentifier, newRunningProcess.icon);
				
				[self runningApplicationsPopUpButtonRequest:nil];
				
				[self.processList unrequestPollingWithObserver:self];
				
				return;
			}
		}
		
		// Otherwise add the new application
		NSMenuItem *menuItem = [[NSMenuItem alloc] init];
		
		ZGUpdateProcessMenuItem(menuItem, newRunningProcess.name, newRunningProcess.processIdentifier, newRunningProcess.icon);
		
		ZGProcess *representedProcess =
		[[ZGProcess alloc]
		 initWithName:newRunningProcess.name
		 internalName:newRunningProcess.internalName
		 processID:newRunningProcess.processIdentifier
		 is64Bit:newRunningProcess.is64Bit];
		
		menuItem.representedObject = representedProcess;
		
		[self.runningApplicationsPopUpButton.menu addItem:menuItem];
		
		// If we found desired process name, select it
		if (![self.currentProcess.internalName isEqualToString:self.documentData.desiredProcessInternalName] &&
			[self.documentData.desiredProcessInternalName isEqualToString:newRunningProcess.internalName])
		{
			[self.runningApplicationsPopUpButton selectItem:menuItem];
			[self runningApplicationsPopUpButtonRequest:nil];
		}
	}
}

- (void)observeValueForKeyPath:(NSString *)__unused keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)__unused context
{
	NSArray *newRunningProcesses = [change objectForKey:NSKeyValueChangeNewKey];
	NSArray *oldRunningProcesses = [change objectForKey:NSKeyValueChangeOldKey];
	
	if (object == self.processList && self.runningApplicationsPopUpButton.itemArray.count > 0)
	{
		if (newRunningProcesses != nil)
		{
			for (ZGRunningProcess *runningProcess in newRunningProcesses)
			{
				[self addRunningProcessToPopupButton:runningProcess];
			}
		}
		
		if (oldRunningProcesses != nil)
		{
			for (ZGRunningProcess *runningProcess in oldRunningProcesses)
			{
				[self removeRunningProcessFromPopupButton:runningProcess];
				
				if ([self.processTaskManager taskExistsForProcessIdentifier:runningProcess.processIdentifier])
				{
					[self.processTaskManager freeTaskForProcessIdentifier:runningProcess.processIdentifier];
				}
			}
		}
	}
	else if (object == [NSWorkspace sharedWorkspace] && self.runningApplicationsPopUpButton.itemArray.count > 0)
	{
		// ZGProcessList may report processes to us faster than NSRunningApplication can ocasionally
		// So be sure to get updated localized name and icon
		for (NSRunningApplication *runningApplication in newRunningProcesses)
		{
			for (NSMenuItem *menuItem in self.runningApplicationsPopUpButton.itemArray)
			{
				ZGProcess *representedProcess = [menuItem representedObject];
				
				if (runningApplication.processIdentifier == representedProcess.processID)
				{
					representedProcess.name = runningApplication.localizedName;
					
					ZGUpdateProcessMenuItem(menuItem, runningApplication.localizedName, runningApplication.processIdentifier, runningApplication.icon);
					
					break;
				}
			}
		}
	}
}

- (BOOL)isClearable
{
	return (self.documentData.variables.count > 0 && [self.searchController canStartTask]);
}

- (void)changeIntegerQualifier:(ZGVariableQualifier)newQualifier
{
	ZGVariableQualifier oldQualifier = (ZGVariableQualifier)self.documentData.qualifierTag;
	if (oldQualifier != newQualifier)
	{
		for (ZGVariable *variable in self.documentData.variables)
		{
			variable.qualifier = newQualifier;
			switch (variable.type)
			{
				case ZGInt8:
				case ZGInt16:
				case ZGInt32:
				case ZGInt64:
					[variable updateStringValue];
					break;
				case ZGString8:
				case ZGString16:
				case ZGByteArray:
				case ZGScript:
				case ZGPointer:
				case ZGFloat:
				case ZGDouble:
					break;
			}
		}
		
		[self.tableController.variablesTableView reloadData];
		[self markDocumentChange];
		
		self.documentData.qualifierTag = newQualifier;
	}
}

- (void)setFlagsLabelStringValue:(NSString *)flagsLabelStringValue
{
	_flagsLabelStringValue = [flagsLabelStringValue copy];
	[self.flagsLabel setStringValue:_flagsLabelStringValue];
}

- (void)setFlagsStringValue:(NSString *)flagsStringValue
{
	_flagsStringValue = [flagsStringValue copy];
	[self.flagsTextField setStringValue:_flagsStringValue];
}

- (IBAction)changeFlags:(id)sender
{
	[self setFlagsStringValue:[sender stringValue]];
}

- (void)updateFlagsRangeTextField
{
	ZGFunctionType functionType = (ZGFunctionType)self.functionPopUpButton.selectedItem.tag;
	if (functionType == ZGGreaterThan || functionType == ZGGreaterThanStored || functionType == ZGGreaterThanStoredLinear)
	{
		self.flagsLabelStringValue = @"Below:";
		
		if (self.documentData.lastBelowRangeValue != nil)
		{
			self.flagsStringValue = self.documentData.lastBelowRangeValue;
		}
		else
		{
			self.flagsStringValue = @"";
		}
	}
	else if (functionType == ZGLessThan || functionType == ZGLessThanStored || functionType == ZGLessThanStoredLinear)
	{
		self.flagsLabelStringValue = @"Above:";
		
		if (self.documentData.lastAboveRangeValue != nil)
		{
			self.flagsStringValue = self.documentData.lastAboveRangeValue;
		}
		else
		{
			self.flagsStringValue = @"";
		}
	}
}

- (void)changeScopeBarGroup:(AGScopeBarGroup *)group shouldExist:(BOOL)shouldExist
{
	BOOL alreadyExists = [self.scopeBar.groups containsObject:group];
	if (alreadyExists)
	{
		[self.scopeBar removeGroupAtIndex:[self.scopeBar.groups indexOfObject:group]];
	}
	
	if (shouldExist)
	{
		[self.scopeBar insertGroup:group atIndex:self.scopeBar.groups.count];
	}
}

- (void)updateOptions
{
	ZGVariableType dataType = [self selectedDataType];
	ZGFunctionType functionType = [self selectedFunctionType];
	
	BOOL needsFlags = NO;
	BOOL needsQualifier = NO;
	BOOL needsStringMatching = NO;
	
	if (dataType == ZGFloat || dataType == ZGDouble)
	{
		if (ZGIsFunctionTypeEquals(functionType) || ZGIsFunctionTypeNotEquals(functionType))
		{
			// epsilon
			self.flagsLabelStringValue = @"Round Error:";
			if (self.documentData.lastEpsilonValue != nil)
			{
				self.flagsStringValue = self.documentData.lastEpsilonValue;
			}
			else
			{
				self.flagsStringValue = @"";
			}
		}
		else
		{
			// range
			[self updateFlagsRangeTextField];
		}
		
		needsFlags = YES;
	}
	else if (dataType == ZGString8 || dataType == ZGString16)
	{
		needsStringMatching = YES;
	}
	else if (dataType != ZGByteArray)
	{
		if (!ZGIsFunctionTypeEquals(functionType) && !ZGIsFunctionTypeNotEquals(functionType))
		{
			// range
			[self updateFlagsRangeTextField];
			
			needsFlags = YES;
		}
		
		if (dataType != ZGPointer)
		{
			needsQualifier = YES;
		}
	}
	
	[self.functionPopUpButton removeAllItems];
	
	[self.functionPopUpButton insertItemWithTitle:@"equals" atIndex:0];
	[[self.functionPopUpButton itemAtIndex:0] setTag:ZGEquals];
	
	[self.functionPopUpButton insertItemWithTitle:@"is not" atIndex:1];
	[[self.functionPopUpButton itemAtIndex:1] setTag:ZGNotEquals];
	
	if (dataType != ZGString8 && dataType != ZGString16 && dataType != ZGByteArray)
	{
		[self.functionPopUpButton insertItemWithTitle:@"is greater than" atIndex:2];
		[[self.functionPopUpButton itemAtIndex:2] setTag:ZGGreaterThan];
		
		[self.functionPopUpButton insertItemWithTitle:@"is less than" atIndex:3];
		[[self.functionPopUpButton itemAtIndex:3] setTag:ZGLessThan];
	}
	
	if (![self.functionPopUpButton selectItemWithTag:self.documentData.functionTypeTag])
	{
		self.documentData.functionTypeTag = self.functionPopUpButton.selectedTag;
	}
	
	BOOL needsEndianness = ZGSupportsEndianness(dataType);
	
	[self changeScopeBarGroup:self.qualifierGroup shouldExist:needsQualifier];
	[self changeScopeBarGroup:self.stringMatchingGroup shouldExist:needsStringMatching];
	[self changeScopeBarGroup:self.endianGroup shouldExist:needsEndianness];
	
	_showsFlags = needsFlags;
	self.scopeBar.accessoryView = _showsFlags ? self.scopeBarFlagsView : nil;
}

- (void)selectDataTypeWithTag:(ZGVariableType)newTag recordUndo:(BOOL)recordUndo
{
	ZGVariableType oldVariableTypeTag = (ZGVariableType)self.documentData.selectedDatatypeTag;
	
	self.documentData.selectedDatatypeTag = newTag;
	[self.dataTypesPopUpButton selectItemWithTag:newTag];
	
	self.functionPopUpButton.enabled = YES;
	
	[self updateOptions];
	
	if (recordUndo && oldVariableTypeTag != newTag)
	{
		[self.undoManager setActionName:@"Data Type Change"];
		[[self.undoManager prepareWithInvocationTarget:self]
		 selectDataTypeWithTag:oldVariableTypeTag
		 recordUndo:YES];
	}
}

- (IBAction)dataTypePopUpButtonRequest:(id)sender
{
	[self selectDataTypeWithTag:(ZGVariableType)[[sender selectedItem] tag] recordUndo:YES];
}

- (ZGVariableType)selectedDataType
{
	return (ZGVariableType)self.documentData.selectedDatatypeTag;
}

- (ZGFunctionType)selectedFunctionType
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	
	BOOL isStoringValues = NO;
	for (id searchValueObject in self.documentData.searchValue)
	{
		if ([searchValueObject isKindOfClass:[ZGSearchToken class]])
		{
			isStoringValues = YES;
			break;
		}
	}
	
	ZGFunctionType functionType = (ZGFunctionType)self.documentData.functionTypeTag;
	if (isStoringValues)
	{
		BOOL isLinearlyExpressedStoredValue = self.documentData.searchValue.count > 1;
		switch (functionType)
		{
			case ZGEquals:
				functionType = isLinearlyExpressedStoredValue ? ZGEqualsStoredLinear : ZGEqualsStored;
				break;
			case ZGNotEquals:
				functionType = isLinearlyExpressedStoredValue ? ZGNotEqualsStoredLinear : ZGNotEqualsStored;
				break;
			case ZGGreaterThan:
				functionType = isLinearlyExpressedStoredValue ? ZGGreaterThanStoredLinear : ZGGreaterThanStored;
				break;
			case ZGLessThan:
				functionType = isLinearlyExpressedStoredValue ? ZGLessThanStoredLinear : ZGLessThanStored;
				break;
			case ZGEqualsStored:
			case ZGNotEqualsStored:
			case ZGGreaterThanStored:
			case ZGLessThanStored:
			case ZGEqualsStoredLinear:
			case ZGNotEqualsStoredLinear:
			case ZGGreaterThanStoredLinear:
			case ZGLessThanStoredLinear:
				break;
		}
	}
	
	return functionType;
}

- (IBAction)functionTypePopUpButtonRequest:(id)sender
{
	self.documentData.functionTypeTag = [sender selectedTag];
	[self updateOptions];
	[self markDocumentChange];
}

#pragma mark Useful Methods

- (void)updateVariables:(NSArray *)newWatchVariablesArray searchResults:(ZGSearchResults *)searchResults
{
	if (self.undoManager.isUndoing || self.undoManager.isRedoing)
	{
		[[self.undoManager prepareWithInvocationTarget:self] updateVariables:self.documentData.variables searchResults:self.searchController.searchResults];
	}
	
	self.documentData.variables = newWatchVariablesArray;
	self.searchController.searchResults = searchResults;
	
	[self.tableController updateWatchVariablesTimer];
	[self.tableController.variablesTableView reloadData];
	
	[self setStatus:nil];
}

#pragma mark Menu item validation

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)menuItem
{
	if (menuItem.action == @selector(clear:))
	{
		if ([self.variableController canClearSearch])
		{
			menuItem.title = @"Clear Search Variables";
		}
		else
		{
			menuItem.title = @"Clear Variables";
		}
		
		if (!self.isClearable)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(storeAllValues:))
	{
		if (!self.currentProcess.valid || ![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(searchPointerToSelectedVariable:))
	{
		if (!self.currentProcess.valid || ![self.searchController canStartTask] || self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		ZGVariable *variable = [self.selectedVariables objectAtIndex:0];
		if (variable.type == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(insertStoredValueToken:))
	{
		if (self.searchData.savedData == nil)
		{
			return NO;
		}
		
		// I'd like to use self.documentData.searchValue but we don't update it instantly
		for (id object in self.searchValueTextField.objectValue)
		{
			if ([object isKindOfClass:[ZGSearchToken class]])
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(removeSelectedSearchValues:))
	{
		if (self.selectedVariables.count == 0 || self.window.firstResponder != self.tableController.variablesTableView)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(freezeVariables:))
	{
		if (self.selectedVariables.count > 0)
		{
			// All the variables selected need to either be all unfrozen or all frozen
			BOOL isFrozen = [[self.selectedVariables objectAtIndex:0] isFrozen];
			BOOL isInconsistent = NO;
			BOOL scriptExists = [(ZGVariable *)[self.selectedVariables objectAtIndex:0] type] == ZGScript;
			
			for (ZGVariable *variable in [self.selectedVariables subarrayWithRange:NSMakeRange(1, self.selectedVariables.count-1)])
			{
				if (variable.isFrozen != isFrozen || !variable.value)
				{
					isInconsistent = YES;
					break;
				}
				else if (variable.type == ZGScript)
				{
					scriptExists = YES;
					break;
				}
			}
			
			menuItem.title = [NSString stringWithFormat:@"%@ Variable%@", isFrozen ? @"Unfreeze" : @"Freeze", self.selectedVariables.count != 1 ? @"s" : @""];
			
			if (isInconsistent || scriptExists || !self.isClearable)
			{
				return NO;
			}
		}
		else
		{
			menuItem.title = @"Freeze Variables";
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(addVariable:))
	{
		if (![self.searchController canStartTask])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copy:))
	{
		if (self.selectedVariables.count == 0)
		{
			return NO;
		}
		
		BOOL isValid = NO;
		for (ZGVariable *variable in self.selectedVariables)
		{
			if (variable.type != ZGScript)
			{
				isValid = YES;
				break;
			}
		}
		
		if (!isValid)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(copyAddress:))
	{
		if (self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self.selectedVariables objectAtIndex:0] type] == ZGScript)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(paste:))
	{
		if ([self.searchController canCancelTask] || ![NSPasteboard.generalPasteboard dataForType:ZGVariablePboardType])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(pauseOrUnpauseProcess:))
	{
		if (!self.currentProcess || !self.currentProcess.valid)
		{
			return NO;
		}
		
		integer_t suspendCount;
		if (!ZGSuspendCount(self.currentProcess.processTask, &suspendCount))
		{
			return NO;
		}
		else
		{
			menuItem.title = [NSString stringWithFormat:@"%@ Target", suspendCount > 0 ? @"Unpause" : @"Pause"];
		}
		
		if ([self.debuggerController isProcessIdentifierHalted:self.currentProcess.processID])
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariablesValue:))
	{
		menuItem.title = [NSString stringWithFormat:@"Edit Variable Value%@…", self.selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || self.selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		for (ZGVariable *variable in self.selectedVariables)
		{
			if (variable.type == ZGScript)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(requestEditingVariableAddress:))
	{
		if ([self.searchController canCancelTask] || self.selectedVariables.count != 1 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		if ([(ZGVariable *)[self.selectedVariables objectAtIndex:0] type] == ZGScript)
		{
			return NO;
		}
	}
    
    else if (menuItem.action == @selector(requestEditingVariablesSize:))
    {
		NSArray *selectedVariables = [self selectedVariables];
		menuItem.title = [NSString stringWithFormat:@"Edit Variable Size%@…", selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		// All selected variables must be Byte Array's
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable.type != ZGByteArray)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(relativizeVariablesAddress:))
	{
		NSArray *selectedVariables = [self selectedVariables];
		if ([self.searchController canCancelTask] || selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		menuItem.title = [NSString stringWithFormat:@"Relativize Variable%@", selectedVariables.count != 1 ? @"s" : @""];
		
		NSArray *machBinaries = [ZGMachBinary machBinariesInProcess:self.currentProcess];
		for (ZGVariable *variable in selectedVariables)
		{
			if (variable.type == ZGScript)
			{
				return NO;
			}
			
			if (variable.usesDynamicAddress)
			{
				return NO;
			}
			
			ZGMachBinary *machBinary = [ZGMachBinary machBinaryNearestToAddress:variable.address fromMachBinaries:machBinaries];
			if (machBinary == nil)
			{
				return NO;
			}
			
			ZGMachBinaryInfo *machBinaryInfo = [machBinary machBinaryInfoInProcess:self.currentProcess];
			if (machBinaryInfo.slide == 0 && machBinary.headerAddress == self.currentProcess.mainMachBinary.headerAddress)
			{
				return NO;
			}
		}
	}
	
	else if (menuItem.action == @selector(watchVariable:))
	{
		if ([self.searchController canCancelTask] || !self.currentProcess.valid || self.selectedVariables.count != 1)
		{
			return NO;
		}
		
		ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
		
		if (selectedVariable.type == ZGScript)
		{
			return NO;
		}
		
		ZGMemoryAddress memoryAddress = selectedVariable.address;
		ZGMemorySize memorySize = selectedVariable.size;
		ZGMemoryProtection memoryProtection;
		
		if (!ZGMemoryProtectionInRegion(self.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			return NO;
		}
		
		if (memoryAddress + memorySize < selectedVariable.address || memoryAddress > selectedVariable.address + selectedVariable.size)
		{
			return NO;
		}
	}
	
	else if (menuItem.action == @selector(nopVariables:))
	{
		menuItem.title = [NSString stringWithFormat:@"NOP Variable%@", self.selectedVariables.count != 1 ? @"s" : @""];
		
		if ([self.searchController canCancelTask] || self.selectedVariables.count == 0 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		BOOL isValid = YES;
		for (ZGVariable *variable in self.selectedVariables)
		{
			if (variable.type != ZGByteArray || !variable.value)
			{
				isValid = NO;
				break;
			}
		}
		
		return isValid;
	}
	
	else if (menuItem.action == @selector(showMemoryViewer:) || menuItem.action == @selector(showDebugger:))
	{
		if (self.selectedVariables.count != 1 || !self.currentProcess.valid)
		{
			return NO;
		}
		
		ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
		
		if (selectedVariable.type == ZGScript)
		{
			return NO;
		}
		
		ZGMemoryAddress memoryAddress = selectedVariable.address;
		ZGMemorySize memorySize = selectedVariable.size;
		ZGMemoryProtection memoryProtection;
		
		if (!ZGMemoryProtectionInRegion(self.currentProcess.processTask, &memoryAddress, &memorySize, &memoryProtection))
		{
			return NO;
		}
		
		if (memoryAddress > selectedVariable.address || memoryAddress + memorySize <= selectedVariable.address)
		{
			return NO;
		}
		
		if (!(memoryProtection & VM_PROT_READ))
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark Search Field Tokens

- (void)deselectSearchField
{
	NSText *fieldEditor = [self.searchValueTextField currentEditor];
	if (fieldEditor != nil)
	{
		fieldEditor.selectedRange = NSMakeRange(fieldEditor.string.length, 0);
		[fieldEditor setNeedsDisplay:YES];
	}
}

- (IBAction)insertStoredValueToken:(id)__unused sender
{
	self.searchValueTextField.objectValue = @[[[ZGSearchToken alloc] initWithName:@"Stored Value"]];
	[self deselectSearchField];
}

- (id)tokenField:(NSTokenField *)__unused tokenField representedObjectForEditingString:(NSString *)editingString
{
	return editingString;
}

- (NSString *)tokenField:(NSTokenField *)__unused tokenField displayStringForRepresentedObject:(id)representedObject
{
	NSString *result = nil;
	if ([representedObject isKindOfClass:[NSString class]])
	{
		result = representedObject;
	}
	else if ([representedObject isKindOfClass:[ZGSearchToken class]])
	{
		result = [representedObject name];
	}
	
	return result;
}

- (NSTokenStyle)tokenField:(NSTokenField *)__unused tokenField styleForRepresentedObject:(id)representedObject
{
	return ([representedObject isKindOfClass:[ZGSearchToken class]]) ? NSRoundedTokenStyle : NSPlainTextTokenStyle;
}

- (NSString *)tokenField:(NSTokenField *)__unused tokenField editingStringForRepresentedObject:(id)representedObject
{
	return ([representedObject isKindOfClass:[ZGSearchToken class]]) ? nil : representedObject;
}

#pragma mark Search Handling

- (IBAction)clear:(id)__unused sender
{
	[self.variableController clear];
}

- (IBAction)clearSearchValues:(id)__unused sender
{
	[self.variableController clearSearch];
}

- (IBAction)searchValue:(id)__unused sender
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	
	if (self.documentData.searchValue.count == 0 && self.searchController.canCancelTask)
	{
		[self.searchController cancelTask];
	}
	else if (self.documentData.searchValue.count == 0 && [self isClearable])
	{
		[self clearSearchValues:nil];
	}
	else if (self.documentData.searchValue.count > 0 && self.searchController.canStartTask && self.currentProcess.valid)
	{
		if (ZGIsFunctionTypeStore([self selectedFunctionType]) && self.searchData.savedData == nil)
		{
			NSRunAlertPanel(@"No Stored Values Available", @"There are no stored values to compare against. Please store values first before proceeding.", nil, nil, nil);
		}
		else
		{
			if (self.documentData.variables.count == 0)
			{
				[self.undoManager removeAllActions];
			}
			
			[self.searchController searchComponents:self.documentData.searchValue withDataType:self.selectedDataType functionType:self.selectedFunctionType allowsNarrowing:YES];
		}
	}
}

- (IBAction)searchPointerToSelectedVariable:(id)__unused sender
{
	ZGVariable *variable = [self.selectedVariables objectAtIndex:0];
	
	[self.searchController searchComponents:@[variable.addressStringValue] withDataType:ZGPointer functionType:ZGEquals allowsNarrowing:NO];
}

- (void)createSearchMenu
{
	NSMenu *searchMenu = [[NSMenu alloc] init];
	NSMenuItem *storedValuesMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stored Value" action:@selector(insertStoredValueToken:) keyEquivalent:@""];
	[searchMenu addItem:storedValuesMenuItem];
	self.searchValueTextField.cell.searchMenu = searchMenu;
}

- (IBAction)storeAllValues:(id)__unused sender
{
	self.documentData.searchValue = self.searchValueTextField.objectValue;
	[self.searchController storeAllValues];
}

- (IBAction)showAdvancedOptions:(id)sender
{
	if (self.advancedOptionsPopover == nil)
	{
		self.advancedOptionsPopover = [[NSPopover alloc] init];
		self.advancedOptionsPopover.contentViewController = [[ZGDocumentOptionsViewController alloc] initWithDocument:self.document];
		self.advancedOptionsPopover.behavior = NSPopoverBehaviorTransient;
	}
	
	[self.advancedOptionsPopover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxYEdge];
}

#pragma mark Variables Handling

- (IBAction)freezeVariables:(id)__unused sender
{
	[self.variableController freezeVariables];
}

- (IBAction)copy:(id)__unused sender
{
	[self.variableController copyVariables];
}

- (IBAction)copyAddress:(id)__unused sender
{
	[self.variableController copyAddress];
}

- (IBAction)paste:(id)__unused sender
{
	[self.variableController pasteVariables];
}

- (IBAction)cut:(id)__unused sender
{
	[self.variableController copyVariables];
	[self removeSelectedSearchValues:nil];
}

- (IBAction)removeSelectedSearchValues:(id)__unused sender
{
	[self.variableController removeSelectedSearchValues];
}

- (IBAction)addVariable:(id)sender
{
	[self.variableController addVariable:sender];
}

- (IBAction)nopVariables:(id)__unused sender
{
	[self.variableController nopVariables:[self selectedVariables]];
}

- (IBAction)requestEditingVariablesValue:(id)__unused sender
{
	if (self.editValueWindowController == nil)
	{
		self.editValueWindowController = [[ZGEditValueWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editValueWindowController requestEditingValuesFromVariables:self.selectedVariables withProcessTask:self.currentProcess.processTask attachedToWindow:self.window scriptManager:self.scriptManager];
}

- (IBAction)requestEditingVariableDescription:(id)__unused sender
{
	if (self.editDescriptionWindowController == nil)
	{
		self.editDescriptionWindowController = [[ZGEditDescriptionWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editDescriptionWindowController requestEditingDescriptionFromVariable:[self.selectedVariables objectAtIndex:0] attachedToWindow:self.window];
}

- (IBAction)requestEditingVariableAddress:(id)__unused sender
{
	if (self.editAddressWindowController == nil)
	{
		self.editAddressWindowController = [[ZGEditAddressWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editAddressWindowController requestEditingAddressFromVariable:[self.selectedVariables objectAtIndex:0] attachedToWindow:self.window];
}

- (IBAction)requestEditingVariablesSize:(id)__unused sender
{
	if (self.editSizeWindowController == nil)
	{
		self.editSizeWindowController = [[ZGEditSizeWindowController alloc] initWithVariableController:self.variableController];
	}
	
	[self.editSizeWindowController requestEditingSizesFromVariables:self.selectedVariables attachedToWindow:self.window];
}

- (IBAction)relativizeVariablesAddress:(id)__unused sender
{
	[self.variableController relativizeVariables:[self selectedVariables]];
}

#pragma mark Variable Watching Handling

- (IBAction)watchVariable:(id)sender
{
	if (self.watchVariableWindowController == nil)
	{
		self.watchVariableWindowController = [[ZGWatchVariableWindowController alloc] initWithBreakPointController:self.breakPointController];
	}
	
	[self.watchVariableWindowController watchVariable:[self.selectedVariables objectAtIndex:0] withWatchPointType:(ZGWatchPointType)[sender tag] inProcess:self.currentProcess attachedToWindow:self.window completionHandler:^(NSArray *foundVariables) {
		if (foundVariables.count > 0)
		{
			NSIndexSet *rowIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, foundVariables.count)];
			[self.variableController addVariables:foundVariables atRowIndexes:rowIndexes];
			[ZGVariableController annotateVariables:foundVariables process:self.currentProcess];
			[self.tableController.variablesTableView scrollRowToVisible:0];
		}
	}];
}

#pragma mark Showing Other Controllers

- (IBAction)showMemoryViewer:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
	
	[ZGNavigationPost
	 postShowMemoryViewerWithProcess:self.currentProcess
	 address:selectedVariable.address
	 selectionLength:selectedVariable.size > 0 ? selectedVariable.size : DEFAULT_MEMORY_VIEWER_SELECTION_LENGTH];
}

- (IBAction)showDebugger:(id)__unused sender
{
	ZGVariable *selectedVariable = [[self selectedVariables] objectAtIndex:0];
	[ZGNavigationPost postShowDebuggerWithProcess:self.currentProcess address:selectedVariable.address];
}

#pragma mark Pausing and Unpausing Processes

- (IBAction)pauseOrUnpauseProcess:(id)__unused sender
{
	[ZGProcess pauseOrUnpauseProcessTask:self.currentProcess.processTask];
}

@end
