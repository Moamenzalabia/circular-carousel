//
//  RACarousel_GestureRecognizer.swift
//  RACarousel
//
//  Created by Piotr Suwara on 10/1/19.
//  Copyright © 2019 Piotr Suwara. All rights reserved.
//

import Foundation

extension RACarousel {
    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        dragging = false
        scrolling = false
        decelerating = false
        
        if gesture is UITapGestureRecognizer {
            var indexVal = index(forViewOrSuperview: touch.view)
            if indexVal == NSNotFound {
                indexVal = index(forViewOrSuperview: touch.view?.subviews.last)
            }
            
            if indexVal != NSNotFound {
                if touch.view!.overrides(#selector(touchesBegan(_:with:))) {
                    return false
                }
            }
        } else if gesture is UIPanGestureRecognizer {
            if touch.view!.overrides(#selector(touchesMoved(_:with:))) {
                if let scrollView = viewOrSuperView(touch.view, asClass: UIScrollView.self) as? UIScrollView {
                    return !scrollView.isScrollEnabled ||
                        (scrollView.contentSize.width <= scrollView.frame.size.width)
                }
                
                if viewOrSuperView(touch.view, asClass: UIButton.self) != nil ||
                    viewOrSuperView(touch.view, asClass: UIBarButtonItem.self) != nil {
                    return true
                }
                return false
            }
        }
        
        return true
    }
    
    override open func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if let panGesture = gesture as? UIPanGestureRecognizer {
            let translation = panGesture.translation(in: self)
            return abs(translation.x) >= abs(translation.y)
        }
        
        return true
    }
    
    @objc internal func didTap(withGesture gesture: UITapGestureRecognizer) {
        let itemViewAtPoint: UIView? = itemView(atPoint: gesture.location(in: contentView))
        let index = indexOfItem(forView: itemViewAtPoint)
        if index != NSNotFound {
            let shouldSelect = delegate?.carousel(self, shouldSelectItemAtIndex: index) ?? true
            if shouldSelect {
                if index != currentItemIdx {
                    scroll(toItemAtIndex: index, animated: true)
                }
                delegate?.carousel(self, didSelectItemAtIndex: index)
            }
        } else {
            scroll(toItemAtIndex: currentItemIdx, animated: true)
        }
    }
    
    @objc internal func didPan(withGesture gesture: UIPanGestureRecognizer) {
        if scrollEnabled && numberOfItems > 0 {
            switch gesture.state {
            case .began:
                dragging = true
                scrolling = false
                decelerating = false
                previousTranslation = gesture.translation(in: self).x
            //delegate?.carouselWillBeginDragging(self)
            case .ended, .cancelled, .failed:
                dragging = false
                didDrag = true
                if shouldDecelerate() {
                    didDrag = false
                    startDecelerating()
                }
                
                pushAnimationState(enabled: true)
                //delegate?.carouselDidEndDragging(self)
                popAnimationState()
                
                if !decelerating {
                    if abs(_scrollOffset - clampedOffset(_scrollOffset)) > RACarouselConstants.FloatErrorMargin {
                        if abs(scrollOffset - CGFloat(currentItemIdx)) < RACarouselConstants.FloatErrorMargin {
                            scroll(toItemAtIndex: currentItemIdx, withDuration: 0.01)
                        }
                    } else if shouldScroll() {
                        let direction: Int = Int(startVelocity / abs(startVelocity))
                        scroll(toItemAtIndex: currentItemIdx + direction, animated: true)
                    } else {
                        scroll(toItemAtIndex: currentItemIdx, animated: true)
                    }
                } else {
                    depthSortViews()
                }
            case .changed:
                let translation: CGFloat = gesture.translation(in: self).x
                let velocity: CGFloat = gesture.velocity(in: self).x
                
                var factor: CGFloat = 1.0
                
                if !wrapEnabled && bounceEnabled {
                    factor = 1.0 - min (abs(_scrollOffset - clampedOffset(_scrollOffset)), bounceDist) / bounceDist
                }
                
                startVelocity = -velocity * factor * scrollSpeed / (CGFloat(itemWidth))
                _scrollOffset = _scrollOffset - ((translation - previousTranslation) * factor * offsetMultiplier / itemWidth)
                previousTranslation = translation
                didScroll()
            case .possible:
                // Do nothing
                break
            }
        }
    }
    
    @objc internal func didSwipe(withGesture gesture: UISwipeGestureRecognizer) {
        
        guard scrollEnabled && numberOfItems > 1 else { return }
        guard scrolling == false && decelerating == false else { return }
        
        switch gesture.direction {
        case UISwipeGestureRecognizer.Direction.right:
            guard currentItemIdx > 0 else { return }
            scroll(toItemAtIndex: currentItemIdx - 1, animated: true)
            
        case UISwipeGestureRecognizer.Direction.left:
            guard currentItemIdx < numberOfItems - 1 else { return }
            scroll(toItemAtIndex: currentItemIdx + 1, animated: true)
            
        default:
            // Do nothing
            break
        }
    }
}
