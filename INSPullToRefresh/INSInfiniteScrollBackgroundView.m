//
//  INSInfinityScrollBackgroundView.m
//  INSPullToRefresh
//
//  Created by Michał Zaborowski on 19.02.2015.
//  Copyright (c) 2015 inspace.io. All rights reserved.
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

#import "INSInfiniteScrollBackgroundView.h"
#import "UIScrollView+INSPullToRefresh.h"

static CGFloat const INSInfinityScrollContentInsetAnimationTime = 0.3;

@interface INSInfiniteScrollBackgroundView ()
@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic, readwrite) INSInfiniteScrollBackgroundViewState state;
@property (nonatomic, assign) UIEdgeInsets externalContentInset;
@property (nonatomic, assign, getter = isUpdatingScrollViewContentInset) BOOL updatingScrollViewContentInset;
@property (nonatomic, assign) CGFloat infiniteScrollBottomContentInset;
@property (nonatomic, assign) CGFloat infiniteScrollRightContentInset;
@end

@implementation INSInfiniteScrollBackgroundView

- (void)setPreserveContentInset:(BOOL)preserveContentInset {
    if (_preserveContentInset != preserveContentInset) {
        _preserveContentInset = preserveContentInset;
        
        if (!_horizontalMode && self.bounds.size.height > 0.0f) {
            [self resetFrame];
        } else if (_horizontalMode && self.bounds.size.width > 0.0f) {
            [self resetFrame];
        }
    }
}

- (void)setEnabled:(BOOL)enabled {
    if (_enabled != enabled) {
        _enabled = enabled;

        if (_enabled) {
            [self resetFrame];
        } else {
            [self endInfiniteScrollingWithStoppingContentOffset:YES];
        }

        if (!self.shouldShowWhenDisabled) {
            self.hidden = !_enabled;
        }

    }
}

- (void)setShouldShowWhenDisabled:(BOOL)shouldShowWhenDisabled {
    if (_shouldShowWhenDisabled != shouldShowWhenDisabled) {
        _shouldShowWhenDisabled = shouldShowWhenDisabled;
        if (_shouldShowWhenDisabled) {
            self.hidden = NO;
        } else {
            self.hidden = (self.state == INSInfiniteScrollBackgroundViewStateNone);
        }
    }
}

#pragma mark - Initializers

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithHeight:0.0f scrollView:nil];
}

- (instancetype)initWithHeight:(CGFloat)height scrollView:(UIScrollView *)scrollView {
    NSParameterAssert(height > 0.0f);
    NSParameterAssert(scrollView);

    CGRect frame = CGRectMake(0.0f, 0.0f, 0.0f, height);
    if (self = [super initWithFrame:frame]) {
        _horizontalMode = NO;
        _atEnd = YES;

        _scrollView = scrollView;
        _externalContentInset = scrollView.contentInset;
        [self commonInit];
    }

    return self;
}

- (instancetype)initWithWidth:(CGFloat)width atEnd:(BOOL)atEnd scrollView:(UIScrollView *)scrollView
{
    NSParameterAssert(width > 0.0f);
    NSParameterAssert(scrollView);
    
    CGRect frame = CGRectMake(0.0f, 0.0f, width, 0.0f);
    if (self = [super initWithFrame:frame]) {
        _horizontalMode = YES;
        _atEnd = atEnd;

        _scrollView = scrollView;
        _externalContentInset = scrollView.contentInset;
        [self commonInit];
    }
    
    return self;
}

- (void)commonInit
{
    _additionalOffsetForInfinityScrollTrigger = 0;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _state = INSInfiniteScrollBackgroundViewStateNone;
    _preserveContentInset = NO;
    _enabled = YES;
    self.hidden = !self.shouldShowWhenDisabled;
    
    [self resetFrame];
}

#pragma mark - Observing

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];

    if (self.superview) {
        [self removeObserversFromView:self.superview];
    }

    if (newSuperview) {
        [self addScrollViewObservers:newSuperview];
    }
}

- (void)removeObserversFromView:(UIView *)view {
    NSParameterAssert([view isKindOfClass:[UIScrollView class]]);

    [view removeObserver:self forKeyPath:@"contentOffset"];
    [view removeObserver:self forKeyPath:@"contentSize"];
    [view removeObserver:self forKeyPath:@"frame"];
    [view removeObserver:self forKeyPath:@"contentInset"];
}

- (void)addScrollViewObservers:(UIView *)view {
    NSParameterAssert([view isKindOfClass:[UIScrollView class]]);

    [view addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
    [view addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];
    [view addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
    [view addObserver:self forKeyPath:@"contentInset" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (self.enabled && [keyPath isEqualToString:@"contentOffset"]) {
        [self scrollViewDidScroll:[[change valueForKey:NSKeyValueChangeNewKey] CGPointValue]];
    }
    else if ([keyPath isEqualToString:@"contentSize"]) {
        [self layoutSubviews];
        [self resetFrame];
    }
    else if ([keyPath isEqualToString:@"frame"]) {
        [self layoutSubviews];
    }
    else if ([keyPath isEqualToString:@"contentInset"]) {
        // Prevent to change external content inset when pull to refresh is loading
        if (!_updatingScrollViewContentInset && self.scrollView.ins_pullToRefreshBackgroundView.state == INSPullToRefreshBackgroundViewStateNone) {
            self.externalContentInset = [[change valueForKey:NSKeyValueChangeNewKey] UIEdgeInsetsValue];
            [self resetFrame];
        }
    }
}

- (void)scrollViewDidScroll:(CGPoint)contentOffset {

    if (_horizontalMode) {
        CGFloat contentWidth = [self adjustedWidthFromScrollViewContentSize];
        
        // The lower bound when infinite scroll should kick in
        CGFloat actionOffset = contentWidth - self.scrollView.bounds.size.width + self.scrollView.contentInset.right - self.additionalOffsetForInfinityScrollTrigger;
        // Prevent conflict with pull to refresh when tableView is too short
        actionOffset = fmaxf(actionOffset, self.additionalOffsetForInfinityScrollTrigger);
        
        // Disable infinite scroll when scroll view is empty
        // Default UITableView reports height = 1 on empty tables
        BOOL hasActualContent = (self.scrollView.contentSize.width > 1);
        BOOL hasOffsetToStart = (self.atEnd && contentOffset.x > actionOffset) || (!self.atEnd && contentOffset.x < 0);

        if([self.scrollView isDragging] && hasActualContent && hasOffsetToStart) {
            if(self.state == INSInfiniteScrollBackgroundViewStateNone) {
                [self startInfiniteScroll];
            }
        }
    } else {
        CGFloat contentHeight = [self adjustedHeightFromScrollViewContentSize];
        
        // The lower bound when infinite scroll should kick in
        CGFloat actionOffset = contentHeight - self.scrollView.bounds.size.height + self.scrollView.contentInset.bottom - self.additionalOffsetForInfinityScrollTrigger;
        // Prevent conflict with pull to refresh when tableView is too short
        actionOffset = fmaxf(actionOffset, self.additionalOffsetForInfinityScrollTrigger);
        
        // Disable infinite scroll when scroll view is empty
        // Default UITableView reports height = 1 on empty tables
        BOOL hasActualContent = (self.scrollView.contentSize.height > 1);
        
        if([self.scrollView isDragging] && hasActualContent && contentOffset.y > actionOffset) {
            if(self.state == INSInfiniteScrollBackgroundViewStateNone) {
                [self startInfiniteScroll];
            }
        }
    }
}

#pragma mark - Public

- (void)beginInfiniteScrolling {
    if (!self.enabled) {
        return;
    }

    if (self.state == INSInfiniteScrollBackgroundViewStateNone) {
        [self startInfiniteScroll];
    }
}
- (void)endInfiniteScrolling {
    [self endInfiniteScrollingWithStoppingContentOffset:YES];
}

- (void)endInfiniteScrollingWithStoppingContentOffset:(BOOL)stopContentOffset {
    if(self.state == INSInfiniteScrollBackgroundViewStateLoading) {
        [self stopInfiniteScrollWithStoppingContentOffset:stopContentOffset];
    }
}

#pragma mark - Private

- (void)changeState:(INSInfiniteScrollBackgroundViewState)state {
    if (self.state == state) {
        return;
    }
    self.state = state;
    if ([self.delegate respondsToSelector:@selector(infinityScrollBackgroundView:didChangeState:)]) {
        [self.delegate infinityScrollBackgroundView:self didChangeState:state];
    }
}

- (CGFloat)adjustedHeightFromScrollViewContentSize {
    if (self.scrollView.contentSize.height <= 0) {
        return 0;
    }
    CGFloat remainingHeight = self.bounds.size.height - self.scrollView.contentInset.top - self.scrollView.contentInset.bottom;
    if(self.scrollView.contentSize.height < remainingHeight) {
        return remainingHeight;
    }
    return self.scrollView.contentSize.height;
}

- (CGFloat)adjustedWidthFromScrollViewContentSize {
    if (self.scrollView.contentSize.width <= 0) {
        return 0;
    }
    CGFloat remainingWidth = self.bounds.size.width - self.scrollView.contentInset.left - self.scrollView.contentInset.right;
    if (self.scrollView.contentSize.width < remainingWidth) {
        return remainingWidth;
    }
    return self.scrollView.contentSize.width;
}

- (void)callInfiniteScrollActionHandler {
    if(self.actionHandler) {
        self.actionHandler(self.scrollView);
    }
}

- (void)startInfiniteScroll {
    self.hidden = NO;

    UIEdgeInsets contentInset = self.scrollView.contentInset;
    
    if (_horizontalMode) {
        if (_atEnd) {
            contentInset.right += CGRectGetWidth(self.frame);
        } else {
            contentInset.left += CGRectGetWidth(self.frame);
        }

        // We have to pad scroll view when content height is smaller than view bounds.
        // This will guarantee that view appears at the very bottom of scroll view.
        CGFloat adjustedContentWidth = [self adjustedWidthFromScrollViewContentSize];
        CGFloat extraRightInset = adjustedContentWidth - self.scrollView.contentSize.width;
        
        // Add empty space padding
        if (_atEnd) {
            contentInset.right += extraRightInset;
        } else {
            contentInset.left += extraRightInset;
        }
        // Save extra inset
        self.infiniteScrollRightContentInset = extraRightInset;
    } else {
        contentInset.bottom += CGRectGetHeight(self.frame);
        
        // We have to pad scroll view when content height is smaller than view bounds.
        // This will guarantee that view appears at the very bottom of scroll view.
        CGFloat adjustedContentHeight = [self adjustedHeightFromScrollViewContentSize];
        CGFloat extraBottomInset = adjustedContentHeight - self.scrollView.contentSize.height;
        
        // Add empty space padding
        contentInset.bottom += extraBottomInset;
        
        // Save extra inset
        self.infiniteScrollBottomContentInset = extraBottomInset;
    }
    
    [self changeState:INSInfiniteScrollBackgroundViewStateLoading];
    
    __weak typeof(self)weakSelf = self;
    [self setScrollViewContentInset:contentInset animated:YES completion:^(BOOL finished) {
        if (finished) {
            [weakSelf scrollToInfiniteIndicatorIfNeeded];
        }
    }];

    // This will delay handler execution until scroll deceleration
    [self performSelector:@selector(callInfiniteScrollActionHandler) withObject:self afterDelay:0.1 inModes:@[ NSDefaultRunLoopMode ]];
}

- (void)stopInfiniteScrollWithStoppingContentOffset:(BOOL)stopContentOffset {
    UIEdgeInsets contentInset = self.scrollView.contentInset;
    
    if (_horizontalMode) {
        if (_atEnd) {
            contentInset.right -= CGRectGetWidth(self.frame);

            // remove extra inset added to pad infinite scroll
            contentInset.right -= self.infiniteScrollRightContentInset;
        } else {
            contentInset.left -= CGRectGetWidth(self.frame);

            // remove extra inset added to pad infinite scroll
            contentInset.left -= self.infiniteScrollRightContentInset;
        }
    } else {
        contentInset.bottom -= CGRectGetHeight(self.frame);
        
        // remove extra inset added to pad infinite scroll
        contentInset.bottom -= self.infiniteScrollBottomContentInset;
    }
    
    CGPoint offset = [self.scrollView contentOffset];
    
    __weak typeof(self)weakSelf = self;
    [self setScrollViewContentInset:contentInset animated:!stopContentOffset completion:^(BOOL finished) {
        
        if (stopContentOffset) {
            weakSelf.scrollView.contentOffset = offset;
        }
        
        if (finished) {
            if (!weakSelf.shouldShowWhenDisabled) {
                weakSelf.hidden = YES;
            }

            [weakSelf resetScrollViewContentInsetWithCompletion:^(BOOL finished) {
                [weakSelf changeState:INSInfiniteScrollBackgroundViewStateNone];
            }];
        }
    }];
}

- (void)resetScrollViewContentInsetWithCompletion:(void(^)(BOOL finished))completion {
    [UIView animateWithDuration:INSInfinityScrollContentInsetAnimationTime
                          delay:0
                        options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
                         [self setScrollViewContentInset:self.externalContentInset];
                     }
                     completion:completion];
}

#pragma mark - ScrollView

- (void)scrollToInfiniteIndicatorIfNeeded {
    if(![self.scrollView isDragging] && self.state == INSInfiniteScrollBackgroundViewStateLoading) {
        if (_horizontalMode) {
            CGFloat contentWidth = [self adjustedWidthFromScrollViewContentSize];
            CGFloat width = CGRectGetWidth(self.frame);
            
            CGFloat rightBarWidth = (self.scrollView.contentInset.right - width);
            CGFloat minX = contentWidth - self.scrollView.bounds.size.width + rightBarWidth;
            CGFloat maxX = minX + width;
            
            if (self.scrollView.contentOffset.x > minX && self.scrollView.contentOffset.y < maxX) {
                [self.scrollView setContentOffset:CGPointMake(maxX, 0) animated:YES];
            }
        } else {
            // adjust content height for case when contentSize smaller than view bounds
            CGFloat contentHeight = [self adjustedHeightFromScrollViewContentSize];
            CGFloat height = CGRectGetHeight(self.frame);
            
            CGFloat bottomBarHeight = (self.scrollView.contentInset.bottom - height);
            CGFloat minY = contentHeight - self.scrollView.bounds.size.height + bottomBarHeight;
            CGFloat maxY = minY + height;
            
            
            if(self.scrollView.contentOffset.y > minY && self.scrollView.contentOffset.y < maxY) {
                [self.scrollView setContentOffset:CGPointMake(0, maxY) animated:YES];
            }
        }
    }
}

- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset animated:(BOOL)animated completion:(void(^)(BOOL finished))completion {

    void (^updateBlock)(void) = ^{
        [self setScrollViewContentInset:contentInset];
    };

    if(animated) {
        [UIView animateWithDuration:INSInfinityScrollContentInsetAnimationTime
                              delay:0.0
                            options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState)
                         animations:updateBlock
                         completion:completion];
    } else {
        [UIView performWithoutAnimation:updateBlock];

        if(completion) {
            completion(YES);
        }
    }
}

- (void)setScrollViewContentInset:(UIEdgeInsets)contentInset {
    BOOL alreadyUpdating = _updatingScrollViewContentInset; // Check to prevent errors from recursive calls.
    if (!alreadyUpdating) {
        self.updatingScrollViewContentInset = YES;
    }
    if (!UIEdgeInsetsEqualToEdgeInsets(contentInset, self.scrollView.contentInset)) {
        self.scrollView.contentInset = contentInset;
    }
    if (!alreadyUpdating) {
        self.updatingScrollViewContentInset = NO;
    }
}

#pragma mark - Utilities

- (void)resetFrame {
    if (_horizontalMode) {
        CGFloat width = CGRectGetWidth(self.bounds);
        CGFloat contentWidth = [self adjustedWidthFromScrollViewContentSize];
        
        if (_preserveContentInset) {
            if (_atEnd) {
                self.frame = CGRectMake(contentWidth + _externalContentInset.right,
                                        0.0f,
                                        width,
                                        CGRectGetHeight(_scrollView.bounds));
            } else {
                self.frame = CGRectMake(-width - _externalContentInset.left,
                                        0.0f,
                                        width,
                                        CGRectGetHeight(_scrollView.bounds));
            }
        }
        else {
            if (_atEnd) {
                self.frame = CGRectMake(contentWidth,
                                        -_externalContentInset.top,
                                        width,
                                        CGRectGetHeight(_scrollView.bounds));
            } else {
                self.frame = CGRectMake(-width,
                                        -_externalContentInset.top,
                                        width,
                                        CGRectGetHeight(_scrollView.bounds));
            }
        }
    } else {
        CGFloat height = CGRectGetHeight(self.bounds);
        CGFloat contentHeight = [self adjustedHeightFromScrollViewContentSize];
        
        if (_preserveContentInset) {
            self.frame = CGRectMake(0.0f,
                                    contentHeight + _externalContentInset.bottom,
                                    CGRectGetWidth(_scrollView.bounds),
                                    height);
        }
        else {
            self.frame = CGRectMake(-_externalContentInset.left,
                                    contentHeight,
                                    CGRectGetWidth(_scrollView.bounds),
                                    height);
        }
    }
}

@end
