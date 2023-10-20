//
//  GameViewController.swift
//  Protein
//
//  Created by Jana on 8/29/23.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    
    //camera
    var camera = FlyCamera()
    var keysPressed = [Bool](repeating: false, count: Int(UInt16.max))
    var previousMousePoint = NSPoint.zero
    var currentMousePoint = NSPoint.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load the file
        let url = URL(fileURLWithPath: "/Users/jana/LocalDesktop/parsingPDB/protein.pdb")
        let atoms = parsePDB(url: url)
        
        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView, atoms: atoms) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        
        //camera
        Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true) { timer in
            self.updateCamera()
        }
    }
    
    //add all camera stuff below
    override func viewDidAppear() {
        self.view.window?.makeFirstResponder(self)
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    func updateCamera() {
        let timestep: Float = 1 / 60.0
        
        let cursorDeltaX = Float(currentMousePoint.x - previousMousePoint.x)
        let cursorDeltaY = Float(currentMousePoint.y - previousMousePoint.y)
        previousMousePoint = currentMousePoint
        
        let forwardPressed = keysPressed[kVK_ANSI_W]
        let backwardPressed = keysPressed[kVK_ANSI_S]
        let leftPressed = keysPressed[kVK_ANSI_A]
        let rightPressed = keysPressed[kVK_ANSI_D]
        
        camera.update(timestep: timestep,
                      mouseDelta: SIMD2<Float>(cursorDeltaX, cursorDeltaY),
                      forwardPressed: forwardPressed, leftPressed: leftPressed,
                      backwardPressed: backwardPressed, rightPressed: rightPressed)
        
        self.renderer.viewMatrix = camera.viewMatrix
    }
    
    override func mouseDown(with event: NSEvent) {
        let mouseLocation = self.view.convert(event.locationInWindow, from: nil)
        currentMousePoint = mouseLocation
        previousMousePoint = mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseLocation = self.view.convert(event.locationInWindow, from: nil)
        //previousMousePoint = currentMousePoint
        currentMousePoint = mouseLocation
    }
    
    override func mouseUp(with event: NSEvent) {
        let mouseLocation = self.view.convert(event.locationInWindow, from: nil)
        previousMousePoint = mouseLocation
        currentMousePoint = mouseLocation
    }

    override func keyDown(with event: NSEvent) {
        keysPressed[Int(event.keyCode)] = true
    }

    override func keyUp(with event: NSEvent) {
        keysPressed[Int(event.keyCode)] = false
    }
}
