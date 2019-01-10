//
//  RACarousel.swift
//  RACarousel Demo
//
//  Created by Piotr Suwara on 24/12/18.
//  Copyright © 2018 Piotr Suwara. All rights reserved.
//
//  Simplified adaptation of iCarousel in Swift. Additional features added for unique scale effect.
//
//  iCarousel
//  - https://github.com/nicklockwood/iCarousel

import Foundation
import UIKit

@objc public enum RACarouselOption: Int {
    case wrap = 0
    case showBackfaces
    case visibleItems
    case count
    case spacing
    case fadeMin
    case fadeMax
    case fadeRange
    case fadeMinAlpha
    case offsetMultiplier
    case itemWidth
}

struct RACarouselConstants {
    static let MaximumVisibleItems: Int         = 50
    static let DecelerationMultiplier: CGFloat  = 60.0
    static let ScrollSpeedThreshold: CGFloat    = 2.0
    static let DecelerateThreshold: CGFloat     = 0.1
    static let ScrollDistanceThreshold: CGFloat = 0.1
    static let ScrollDuration: CGFloat          = 0.4
    static let InsertDuration: CGFloat          = 0.4
    static let MinScale: CGFloat                = 0.75
    static let MaxScale: CGFloat                = 1.1
    
    static let MinToggleDuration: TimeInterval  = 0.2
    static let MaxToggleDuration: TimeInterval  = 0.4
    
    static let FloatErrorMargin: CGFloat        = 0.000001
}

@IBDesignable open class RACarousel: UIView {
    
    // Delegate and Datasource
    internal var _delegate: RACarouselDelegate?
    public var delegate: RACarouselDelegate? {
        get {
            return _delegate
        }
        set {
            _delegate = newValue
            if let _ = _delegate, let _ = _dataSource {
                setNeedsLayout()
            }
        }
    }
    
    internal var _dataSource: RACarouselDataSource?
    public var dataSource: RACarouselDataSource? {
        get {
            return _dataSource
        }
        set {
            _dataSource = newValue
            if let _ = _dataSource {
                reloadData()
            }
        }
    }
    
    // Public Variables
    internal (set) public var numberOfItems: Int = 0
    
    var currentItemIdx: Int {
        get {
            return clampedIndex(Int(round(Float(scrollOffset))))
        }
        set {
            assert(newValue < numberOfItems, "Attempting to set the current item outside the bounds of total items")
            
            scrollOffset = CGFloat(newValue)
        }
    }
    
    var scrollEnabled: Bool = true
    var pagingEnabled: Bool = false
    
    @IBInspectable public var wrapEnabled: Bool = true
    @IBInspectable public var bounceEnabled: Bool = true
    
    @IBInspectable public var tapEnabled: Bool {
        get {
            return tapGesture != nil
        }
        
        set {
            if tapGesture != nil, newValue == false {
                contentView.removeGestureRecognizer(tapGesture!)
                tapGesture = nil
            } else if tapGesture == nil && newValue == true {
                tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
                tapGesture?.delegate = self as? UIGestureRecognizerDelegate
                contentView.addGestureRecognizer(tapGesture!)
            }
        }
    }
    
    @IBInspectable public var swipeEnabled: Bool {
        get {
            return swipeLeftGesture != nil && swipeRightGesture != nil
        }
        
        set {
            if newValue == false {
                if swipeRightGesture != nil {
                    contentView.removeGestureRecognizer(swipeRightGesture!)
                    swipeRightGesture = nil
                }
                
                if swipeLeftGesture != nil {
                    contentView.removeGestureRecognizer(swipeLeftGesture!)
                    swipeLeftGesture = nil
                }
                
            } else if swipeLeftGesture == nil && swipeRightGesture == nil && newValue == true {
                swipeLeftGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
                swipeLeftGesture?.direction = .left
                swipeLeftGesture?.delegate = self as? UIGestureRecognizerDelegate
                contentView.addGestureRecognizer(swipeLeftGesture!)
                
                swipeRightGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
                swipeRightGesture?.direction = .right
                swipeRightGesture?.delegate = self as? UIGestureRecognizerDelegate
                contentView.addGestureRecognizer(swipeRightGesture!)
            }
        }
    }
    
    @IBInspectable public var panEnabled: Bool {
        get {
            return panGesture != nil
        }
        
        set {
            if panGesture != nil, newValue == false {
                contentView.removeGestureRecognizer(panGesture!)
                panGesture = nil
            } else if panGesture == nil && newValue == true {
                panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
                panGesture?.delegate = self as? UIGestureRecognizerDelegate
                contentView.addGestureRecognizer(panGesture!)
            }
        }
    }
    
    internal var _scrollOffset: CGFloat = 0.0
    var scrollOffset: CGFloat {
        get {
            return _scrollOffset
        } set {
            scrolling = false
            decelerating = false
            startOffset = scrollOffset
            endOffset = scrollOffset
            
            if (abs(_scrollOffset - newValue) > 0.0) {
                _scrollOffset = newValue
                depthSortViews()
                didScroll()
            }
        }
    }
    
    internal var _contentOffset: CGSize = CGSize.zero
    var contentOffset: CGSize {
        get {
            return _contentOffset
        }
        set {
            if _contentOffset != newValue {
                _contentOffset = newValue
                layoutItemViews()
            }
        }
    }
    
    internal (set) public var viewPointOffset: CGSize = CGSize.zero
    
    // Accessible Variables
    var currentItemView: UIView! {
        get {
            return itemView(atIndex: currentItemIdx)
        }
        set {
            // Do something?
        }
    }
    
    internal (set) public var numberOfVisibleItems: Int = 0
    internal (set) public var itemWidth: CGFloat = 0.0
    internal (set) public var offsetMultiplier: CGFloat = 1.0
    internal (set) public var toggle: CGFloat = 0.0
    
    internal (set) public var contentView: UIView = UIView()
    
    internal (set) public var dragging: Bool = false
    internal (set) public var scrolling: Bool = false
    
    // internal variables
    var itemViews: Dictionary<Int, UIView> = Dictionary<Int, UIView>()
    var previousItemIndex: Int = 0
    var itemViewPool: Set<UIView> = Set<UIView>()
    var prevScrollOffset: CGFloat = 0.0
    var startOffset: CGFloat = 0.0
    var endOffset: CGFloat = 0.0
    var scrollDuration: TimeInterval = 0.0
    var startTime: TimeInterval = 0.0
    var endTime: TimeInterval = 0.0
    var lastTime: TimeInterval = 0.0
    var decelerating: Bool = false
    var decelerationRate: CGFloat = 0.95
    var startVelocity: CGFloat = 0.0
    var timer: Timer?
    var didDrag: Bool = false
    var toggleTime: TimeInterval = 0.0
    var previousTranslation: CGFloat = 0.0
    
    let decelSpeed: CGFloat = 0.9
    let scrollSpeed: CGFloat = 1.0
    let bounceDist: CGFloat = 1.0
    
    var panGesture: UIPanGestureRecognizer?
    var swipeLeftGesture: UISwipeGestureRecognizer?
    var swipeRightGesture: UISwipeGestureRecognizer?
    var tapGesture: UITapGestureRecognizer?
    
    // Public functions
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    convenience init() {
        self.init(frame: CGRect.zero)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        setupView()
        if let _ = self.superview {
            startAnimation()
        }
    }
    
    public func itemView(atIndex index: Int) -> UIView? {
        return itemViews[index]
    }
    
    func setupView() {
        contentView = UIView(frame: self.bounds)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        panGesture?.delegate = self as? UIGestureRecognizerDelegate
        contentView.addGestureRecognizer(panGesture!)
        
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tapGesture?.delegate = self as? UIGestureRecognizerDelegate
        contentView.addGestureRecognizer(tapGesture!)
        
        swipeLeftGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
        swipeLeftGesture?.delegate = self as? UIGestureRecognizerDelegate
        swipeLeftGesture?.direction = .left
        contentView.addGestureRecognizer(swipeLeftGesture!)
        
        swipeRightGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
        swipeRightGesture?.delegate = self as? UIGestureRecognizerDelegate
        swipeRightGesture?.direction = .right
        contentView.addGestureRecognizer(swipeRightGesture!)
        
        accessibilityTraits = UIAccessibilityTraits.allowsDirectInteraction
        isAccessibilityElement = true
        
        addSubview(contentView)
        
        if let _ = dataSource {
            reloadData()
        }
    }
    
    func pushAnimationState(enabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!enabled)
    }
    
    func popAnimationState() {
        CATransaction.commit()
    }
    
    // MARK: -
    // MARK: View Management
    
    public func indexOfItem(forView view: UIView?) -> Int {
        
        guard let aView = view else { return NSNotFound }
        
        if let index = itemViews.values.firstIndex(of: aView) {
            return itemViews.keys[index]
        }
        return NSNotFound
    }
    
    func indexOfItem(forViewOrSubView viewOrSubView: UIView) -> Int {
        let index = indexOfItem(forView: viewOrSubView)
        if index == NSNotFound && self.superview != nil && viewOrSubView != contentView {
            return indexOfItem(forViewOrSubView: self.superview!)
        }
        return index
    }
    
    func itemView(atPoint point: CGPoint) -> UIView? {
        
        // Sort views in order of depth
        let views = itemViews.values.sorted { (a, b) -> Bool in
            return compare(viewDepth: a, withView: b)
        }
        
        for view in views {
            if view.superview?.layer.hitTest(point) != nil {
                return view
            }
        }
        
        return nil
    }
    
    func setItemView(_ view: UIView?, forIndex index: Int) {
        itemViews[index] = view
    }
    
    internal func removeViewAtIndex(_ index: Int) {
        itemViews.removeValue(forKey: index)
        itemViews = Dictionary(uniqueKeysWithValues:
            itemViews.map { (arg: (key: Int, value: UIView)) -> (key: Int, value: UIView) in
                return (key: arg.key < index ? index : index - 1, value: arg.value)
        })
    }
    
    internal func insertView(_ view: UIView?, atIndex index: Int) {
        
        itemViews = Dictionary(uniqueKeysWithValues:
            itemViews.map { (arg: (key: Int, value: UIView)) -> (key: Int, value: UIView) in
                return (key: arg.key < index ? index : index + 1, value: arg.value)
        })
        
        setItemView(view, forIndex: index)
    }
    
    internal func compare(viewDepth viewA: UIView, withView viewB: UIView) -> Bool {
        
        // Given the set of views, return true if A is behind B or if they are equal, check against C (CurrentView)
        guard let superviewA = viewA.superview else { return false }
        guard let superviewB = viewB.superview else { return false }
        
        let transformA = superviewA.layer.transform
        let transformB = superviewB.layer.transform
        
        let zA = transformA.m13 + transformA.m23 + transformA.m33 + transformA.m43
        let zB = transformB.m13 + transformB.m23 + transformB.m33 + transformB.m43
        
        var diff = zA - zB
        
        if diff == 0.0 {
            let transformCurItem = currentItemView.superview!.layer.transform
            
            let xA = transformA.m11 + transformA.m21 + transformA.m31 + transformA.m41
            let xB = transformB.m11 + transformB.m21 + transformB.m31 + transformB.m41
            let xCurItem = transformCurItem.m11 + transformCurItem.m21 + transformCurItem.m31 + transformCurItem.m41
            
            diff = abs(xB - xCurItem) - abs(xA - xB)
        }
        
        return diff < 0.0
    }
    
    // MARK: -
    // MARK: View Queing
    
    @objc internal func queue(itemView view: UIView) {
        itemViewPool.insert(view)
    }
    
    internal func dequeItemView() -> UIView? {
        if let view = itemViewPool.first {
            itemViewPool.remove(view)
            return view
        }
        
        return nil
    }
    
    // MARK: -
    // MARK: View Indexing
    
    internal func index(forViewOrSuperview view: UIView?) -> Int {
        guard let aView = view else { return NSNotFound }
        guard aView != contentView else { return NSNotFound }
        
        let indexVal: Int = indexOfItem(forView: aView)
        if indexVal == NSNotFound {
            return index(forViewOrSuperview: aView.superview)
        }
        
        return indexVal
    }
    
    internal func viewOrSuperView(_ view: UIView?, asClass aClass: AnyClass) -> AnyObject? {
        guard let aView = view else { return nil }
        guard aView != contentView else { return nil }
        
        if type(of: aView) == aClass {
            return aView
        }
        
        return viewOrSuperView(aView.superview, asClass: aClass)
    }
    
    // MARK: -
    // MARK: Clamping
    
    internal func clampedOffset(_ offset: CGFloat) -> CGFloat {
        if numberOfItems == 0 {
            return -1.0
        } else if wrapEnabled {
            return offset - floor(offset / CGFloat(numberOfItems)) * CGFloat(numberOfItems)
        }
        
        return min(max(0.0, offset), max(0.0, CGFloat(numberOfItems) - 1.0))
    }
    
    internal func clampedIndex(_ index: Int) -> Int{
        if numberOfItems == 0 {
            return -1
        } else if wrapEnabled {
            return index - Int(floor(CGFloat(index) / CGFloat(numberOfItems))) * numberOfItems
        }
        
        return min(max(0, index), max(0, numberOfItems - 1))
    }
}
