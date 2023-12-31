//
//  Renderer.swift
//  Protein
//
//  Created by Jana on 8/29/23.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
let maxBuffersInFlight = 3

let instancesBufferSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
//    var colorMap: MTLTexture

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var dynamicUniformBuffer: MTLBuffer
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var uniforms: UnsafeMutablePointer<Uniforms>
    
    // instaces
    var PerInstanceBuffer: MTLBuffer
    var instances: UnsafeMutablePointer<PerInstanceUniforms>
    let instanceCount: Int

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    public var viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0)
    var rotation: Float = 0
    var scale: Float = 0

    var mesh: MTKMesh

    init?(metalKitView: MTKView, atoms: Array<Atom>) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!
        
        // Uniform Buffer
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        self.dynamicUniformBuffer = self.device.makeBuffer(length:uniformBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!
        self.dynamicUniformBuffer.label = "UniformBuffer"
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)

        // Instance Buffer
        instanceCount = atoms.count
        let instanceBufferSize = instancesBufferSize * instanceCount
        self.PerInstanceBuffer = self.device.makeBuffer(length:instanceBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!
        self.PerInstanceBuffer.label = "PerInstanceBuffer"
        instances = UnsafeMutableRawPointer(PerInstanceBuffer.contents()).bindMemory(to: PerInstanceUniforms.self, capacity: atoms.count)
        
        // TODO: Populate instances using atoms
        for (instance, atom) in atoms.enumerated() {
            instances[instance].modelMatrix =
            matrix4x4_scale(Float(0.05), Float(0.05), Float(0.05)) * matrix4x4_translation(atom.x, atom.y, atom.z)
            if atom.type == "O" {
                // Oxygen = Red
                instances[instance].color = SIMD4<Float>(x: 1.0, y: 0.0, z: 0.0, w: 1.0)
            }
            if atom.type == "Cl" {
                // Chlorine = Green
                instances[instance].color = .init(x: 0.0, y: 1.0, z: 0.0, w: 1.0)
            }
            if atom.type == "N" {
                // Nitrogen = Blue
                instances[instance].color = .init(x: 0.0, y: 0.0, z: 1.0, w: 1.0)
            }
            if atom.type == "C" {
                // Carbon = Gray
                instances[instance].color = .init(x: 0.5, y: 0.5, z: 0.5, w: 0.5)
            }
            if atom.type == "S" {
                // Sulphur = Yellow
                instances[instance].color = .init(x: 1.0, y: 1.0, z: 0.0, w: 1.0)
            }
            if atom.type == "P" {
                // Phosphorus = Orange
                instances[instance].color = .init(x: 1.0, y: 0.5, z: 0.0, w: 1.0)
            }
        }
        
        /// define depth buffer
        // depth32Float uses one single-precision float per pixel to track the distance from the camera to the nearest fragment seen so far.
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 4

        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()

        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        /*
         Depth:
         - depth needed to "organize" pixels
         - we want to keep the fragment that is closest to the camera for each pixel, so we use a compare function of .less.
         - We also set isDepthWriteEnabled to true, so that the depth values of passing fragments are actually written to the depth buffer.
         - self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)! -- renderer’s initializer
         */
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!

        do {
            mesh = try Renderer.buildMesh(device: device, mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to build MetalKit Mesh. Error info: \(error)")
            return nil
        }

//        do {
//            colorMap = try Renderer.loadTexture(device: device, textureName: "ColorMap")
//        } catch {
//            print("Unable to load texture. Error info: \(error)")
//            return nil
//        }

        super.init()

    }

    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices

        let mtlVertexDescriptor = MTLVertexDescriptor()

        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        //--------------------------------------------------
        mtlVertexDescriptor.attributes[VertexAttribute.normals.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.normals.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.normals.rawValue].bufferIndex = BufferIndex.meshNormals.rawValue 
        //--------------------------------------------------
        
        // position
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = MemoryLayout<SIMD3<Float32>>.stride
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        // texCoord
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = MemoryLayout<SIMD3<Float32>>.stride
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        // normals
        mtlVertexDescriptor.layouts[BufferIndex.meshNormals.rawValue].stride = MemoryLayout<SIMD3<Float32>>.stride
        mtlVertexDescriptor.layouts[BufferIndex.meshNormals.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshNormals.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }

    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object

        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor

        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    class func buildMesh(device: MTLDevice,
                         mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
        /// Create and condition mesh data to feed into a pipeline using the given vertex descriptor

        let metalAllocator = MTKMeshBufferAllocator(device: device)
        /*
        let mdlMesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(4, 4, 4),
                                     segments: SIMD3<UInt32>(2, 2, 2),
                                     geometryType: MDLGeometryType.triangles,
                                     inwardNormals:false,
                                     allocator: metalAllocator)
        */
        let radius: Float = 1
        let mdlMesh = MDLMesh.newEllipsoid(withRadii: SIMD3<Float>(radius, radius, radius), radialSegments: 10, verticalSegments: 10, geometryType: MDLGeometryType.triangles, inwardNormals: false, hemisphere: false, allocator: metalAllocator)

        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
        guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
            throw RendererError.badVertexDescriptor
        }
        attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
        attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
        attributes[VertexAttribute.normals.rawValue].name = MDLVertexAttributeNormal
        
        mdlMesh.vertexDescriptor = mdlVertexDescriptor

        return try MTKMesh(mesh:mdlMesh, device:device)
    }

//    class func loadTexture(device: MTLDevice,
//                           textureName: String) throws -> MTLTexture {
//        /// Load texture data with optimal parameters for sampling
//        let textureLoader = MTKTextureLoader(device: device)
//        let textureLoaderOptions = [
//            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
//            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
//        ]
//        return try textureLoader.newTexture(name: textureName,
//                                            scaleFactor: 1.0,
//                                            bundle: nil,
//                                            options: textureLoaderOptions)
//    }

    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }

    private func updateGameState() {
        /// Update any game state before rendering
        /// only needed if the state of the game changes, i.e. the objects rotate or whatever. 

        uniforms[0].projectionMatrix = projectionMatrix
        
        ///move up and declare it as public for camera view
//        let viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0)
        uniforms[0].viewMatrix = viewMatrix
        /*
        let rotationAxis = SIMD3<Float>(1, 1, 0)
        rotation += 0.0001
        
        let scaleFactor = sin(scale) * 0.5 + 1
        
        
        for instance in 0..<instanceCount {
            instances[instance].modelMatrix = matrix4x4_rotation(radians: rotation * Float(instance), axis: rotationAxis) *
            matrix4x4_scale(Float(scaleFactor * 0.01), Float(scaleFactor * 0.01), Float(scaleFactor * 0.01)) *
                matrix4x4_translation(1, 10 * Float(instance), 10 * Float(instance))
        }
        */
        
        
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor {
                
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = "Primary Render Encoder"
                    renderEncoder.pushDebugGroup("Draw Box")
                    renderEncoder.setCullMode(.back)
                    renderEncoder.setFrontFacing(.counterClockwise)
                    renderEncoder.setRenderPipelineState(pipelineState)
                    renderEncoder.setDepthStencilState(depthState)
                    
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    
                    renderEncoder.setVertexBuffer(PerInstanceBuffer, offset: 0, index: BufferIndex.instance.rawValue)
                    
                    for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
                        guard let layout = element as? MDLVertexBufferLayout else {
                            return
                        }
                        
                        if layout.stride != 0 {
                            let buffer = mesh.vertexBuffers[index]
                            renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
                        }
                    }
                    
                    
//                    renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
                    
                    for submesh in mesh.submeshes {
                        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                            indexCount: submesh.indexCount,
                                                            indexType: submesh.indexType,
                                                            indexBuffer: submesh.indexBuffer.buffer,
                                                            indexBufferOffset: submesh.indexBuffer.offset,
                                                            instanceCount: instanceCount)
                        
                    }
                     
                    
                    renderEncoder.popDebugGroup()
                    
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix4x4_scale(_ scaleX: Float, _ scaleY: Float, _ scaleZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(scaleX, 0, 0, 0),
                                         vector_float4(0, scaleY, 0, 0),
                                         vector_float4(0, 0, scaleZ, 0),
                                         vector_float4(0, 0, 0, 1)))
}


func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
