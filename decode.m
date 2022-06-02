/*
 * gcc -framework CoreMedia -framework CoreVideo -framework IOSurface -framework Cocoa -framework OpenGL -framework VideoToolbox -lobjc decode.m -o decode
 */

#include <stdio.h>
#include <assert.h>
#include <OpenGL/gl.h>

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "VideoToolbox/VTDecompressionSession.h"


typedef struct H264Sample {
    size_t mSize;
    unsigned char* mData;
    int64_t mTime;
    int64_t mDuration;
} H264Sample;

H264Sample mCodecData;
H264Sample mVideoData;


H264Sample* LoadCodecData()
{
    NSData* h264Data = [[NSData alloc] initWithContentsOfFile: @"/Users/cartier/Devel/jazz/test/hardware/codec.data"];

    size_t size = [h264Data length];
    const void* data = [h264Data bytes];

    mCodecData.mSize = size;
    mCodecData.mData = (unsigned char*) malloc(size);
    memcpy(mCodecData.mData, data, size);
    
    return &mCodecData;
}

H264Sample* LoadVideoData()
{
    NSData* h264Data = [[NSData alloc] initWithContentsOfFile: @"/Users/cartier/Devel/jazz/test/hardware/video.data"];

    size_t size = [h264Data length];
    const void* data = [h264Data bytes];

    mVideoData.mSize = size;
    mVideoData.mData = (unsigned char*) malloc(size);
    memcpy(mVideoData.mData, data, size);
    mVideoData.mTime = 0;
    mVideoData.mDuration = 106666LL;
    
    return &mVideoData;
}


@interface TestView: NSView
{
    NSOpenGLContext* mContext;
    GLuint mProgramID;
    GLuint mTexture;
    GLuint mTextureUniform;
    GLuint mPosAttribute;
    GLuint mVertexbuffer;
    bool mStarted;
}

- (void)output:(IOSurfaceRef)surface;

@end


void OutputFrame(CVPixelBufferRef aImage);


TestView* mView;
NSOpenGLContext* mContext;
int32_t mWidth;
int32_t mHeight;
CMVideoFormatDescriptionRef mFormat;
VTDecompressionSessionRef mSession;
dispatch_queue_t mQueue;


CFDictionaryRef
CreateDecoderExtensions()
{
    H264Sample* codecData = LoadCodecData();
    
    CFDataRef avc_data = CFDataCreate(kCFAllocatorDefault,
                                      codecData->mData,
                                      (CFIndex)codecData->mSize);

    const void* atomsKey[] = { CFSTR("avcC") };
    const void* atomsValue[] = { avc_data };

    CFDictionaryRef atoms =
        CFDictionaryCreate(kCFAllocatorDefault,
                           atomsKey,
                           atomsValue,
                           1,
                           &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);

    const void* extensionKeys[] =
        { kCVImageBufferChromaLocationBottomFieldKey,
          kCVImageBufferChromaLocationTopFieldKey,
          kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms };

    const void* extensionValues[] =
        { kCVImageBufferChromaLocation_Left,
          kCVImageBufferChromaLocation_Left,
          atoms };

    return CFDictionaryCreate(kCFAllocatorDefault,
                              extensionKeys,
                              extensionValues,
                              3,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}


CFDictionaryRef
CreateDecoderSpecification()
{
    const void* specKeys[] = { kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder };
    const void* specValues[] = { kCFBooleanTrue };

    return CFDictionaryCreate(kCFAllocatorDefault,
                              specKeys,
                              specValues,
                              1,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}


CFDictionaryRef
CreateOutputConfiguration()
{
  SInt32 PixelFormatTypeValue = kCVPixelFormatType_422YpCbCr8;
  CFNumberRef PixelFormatTypeNumber =
    CFNumberCreate(kCFAllocatorDefault,
                   kCFNumberSInt32Type,
                   &PixelFormatTypeValue);

  const void* IOSurfaceKeys[] = { };
  const void* IOSurfaceValues[] = { };

  CFDictionaryRef IOSurfaceProperties =
    CFDictionaryCreate(kCFAllocatorDefault,
                       IOSurfaceKeys,
                       IOSurfaceValues,
                       0,
                       &kCFTypeDictionaryKeyCallBacks,
                       &kCFTypeDictionaryValueCallBacks);

  const void* outputKeys[] = { kCVPixelBufferIOSurfacePropertiesKey,
                               kCVPixelBufferPixelFormatTypeKey,
                               kCVPixelBufferOpenGLCompatibilityKey };
  const void* outputValues[] = { IOSurfaceProperties,
                                 PixelFormatTypeNumber,
                                 kCFBooleanTrue };

  return CFDictionaryCreate(kCFAllocatorDefault,
                            outputKeys,
                            outputValues,
                            3,
                            &kCFTypeDictionaryKeyCallBacks,
                            &kCFTypeDictionaryValueCallBacks);
}


IOSurfaceRef mSurface;


// Callback passed to the VideoToolbox decoder for returning data.
// This needs to be static because the API takes a C-style pair of
// function and userdata pointers. This validates parameters and
// forwards the decoded image back to an object method.
static void
DecodeCallback(void* decompressionOutputRefCon,
               void* sourceFrameRefCon,
               OSStatus status,
               VTDecodeInfoFlags flags,
               CVImageBufferRef image,
               CMTime presentationTimeStamp,
               CMTime presentationDuration)
{
    if (status != noErr)
        printf("decoder error %d\n", status);
    else if (!image)
        printf("decoder returned no data\n");
    else if (flags & kVTDecodeInfo_FrameDropped)
        printf("frame was dropped\n");
    else if (CFGetTypeID(image) != CVPixelBufferGetTypeID())
        printf("unexpected image type\n");
    else {
        printf("got image!!!\n");
        CFRetain(image);
        
        printf("111\n");
        mSurface = CVPixelBufferGetIOSurface(image);
        CFRetain(mSurface);
        
        GLsizei width = (GLsizei)IOSurfaceGetWidth(mSurface);
        GLsizei height = (GLsizei)IOSurfaceGetHeight(mSurface);
        printf("222 %d %d\n", width, height);
        
        [mContext makeCurrentContext];
        
        GLuint mTexture = 0;
        glGenTextures(1, &mTexture);
  
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTexture);

        printf("333\n");
        CGLError err = CGLTexImageIOSurface2D([mContext CGLContextObj],
                                              GL_TEXTURE_RECTANGLE_ARB, GL_RGB, width, height,
                                              GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE, mSurface, 0);
        
        char* data = (char*) calloc(width * height * 4, 1);
        printf("before %02x%02x%02x%02x\n", data[0], data[1], data[2], data[3]);
        glGetTexImage(GL_TEXTURE_RECTANGLE_ARB, 0, GL_BGRA, GL_UNSIGNED_BYTE, data);
        printf("after  %02x%02x%02x%02x\n", data[0], data[1], data[2], data[3]);

        printf("444 %d\n", err);
        if (err != kCGLNoError) {
            printf("GL error=%d\n", (int)err);
            return;
        }
        printf("555\n");
        
        dispatch_async(mQueue, ^{
            OutputFrame(image);
            if (image) {
                CFRelease(image);
            }
        });
    }
}


void
OutputFrame(CVPixelBufferRef aImage)
{
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(aImage);

    printf("Returning frame for display\n");
        CFRetain(surface);
        IOSurfaceIncrementUseCount(surface);
    [mView output:surface];
}


bool
InitializeSession(NSOpenGLContext* context, int32_t width, int32_t height)
{
    mContext = context;
    mWidth = width;
    mHeight = height;
    
    OSStatus rv;

    CFDictionaryRef extensions = CreateDecoderExtensions();

    rv = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                        kCMVideoCodecType_H264,
                                        mWidth,
                                        mHeight,
                                        extensions,
                                        &mFormat);
    if (rv != noErr) {
        printf("Couldn't create format description!\n");
        return false;
    }

    CFDictionaryRef spec = CreateDecoderSpecification();

    CFDictionaryRef outputConfiguration =
        CreateOutputConfiguration();

    VTDecompressionOutputCallbackRecord cb = { DecodeCallback, NULL };
    rv = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                      mFormat,
                                      spec,
                                      outputConfiguration,
                                      &cb,
                                      &mSession);

    if (rv != noErr) {
        printf("Couldn't create decompression session!\n");
        return false;
    }

    return true;
}


void DestroySession()
{
    if (mSession) {
        VTDecompressionSessionInvalidate(mSession);
        CFRelease(mSession);
        mSession = NULL;
    }
    if (mFormat) {
        CFRelease(mFormat);
        mFormat = NULL;
    }
}


void CreateDecoder(TestView* aView, NSOpenGLContext* context, int32_t width, int32_t height)
{
    mView = aView;
    InitializeSession(context, width, height);
    mQueue = dispatch_queue_create("com.example.MyQueue", DISPATCH_QUEUE_SERIAL);
}


void DestroyDecoder()
{
    DestroySession();
}


static const int64_t USECS_PER_S = 1000000;

static CMSampleTimingInfo
TimingInfoFromSample(H264Sample* aSample)
{
  CMSampleTimingInfo timestamp;

  timestamp.duration = CMTimeMake(aSample->mDuration, USECS_PER_S);
  timestamp.presentationTimeStamp = CMTimeMake(aSample->mTime, USECS_PER_S);
  timestamp.decodeTimeStamp = CMTimeMake(aSample->mTime, USECS_PER_S);

  return timestamp;
}


bool
DoDecode(H264Sample* aSample)
{
    // For some reason this gives me a double-free error with stagefright.
    CMBlockBufferRef block = NULL;
    CMSampleBufferRef sample = NULL;
    VTDecodeInfoFlags infoFlags;
    OSStatus rv;
    
    rv = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                            (uint8_t*)(aSample->mData),
                                            aSample->mSize,
                                            kCFAllocatorNull,
                                            NULL,
                                            0,
                                            aSample->mSize,
                                            false,
                                            &block);
    if (rv != noErr) {
        printf("Couldn't create CMBlockBuffer\n");
        return false;
    }
    CMSampleTimingInfo timestamp = TimingInfoFromSample(aSample);
    rv = CMSampleBufferCreate(kCFAllocatorDefault, block, true, 0, 0, mFormat, 1, 1, &timestamp, 0, NULL, &sample);
    if (rv != noErr) {
        printf("Couldn't create CMSampleBuffer\n");
        return false;
    }

    VTDecodeFrameFlags decodeFlags =
        kVTDecodeFrame_EnableAsynchronousDecompression;
    rv = VTDecompressionSessionDecodeFrame(mSession,
                                           sample,
                                           decodeFlags,
                                           aSample,
                                           &infoFlags);
    if (rv != noErr) { // BAZOO && !(infoFlags & kVTDecodeInfo_FrameDropped)) {
        printf("decode error %d\n", rv);
        return false;
    }

    return true;
}


void
DecodeNextFrame()
{
    H264Sample* sample = LoadVideoData();
    DoDecode(sample);
}


void
NotifyFrameNeeded()
{
    dispatch_async(mQueue, ^{
        DecodeNextFrame();
    });
}


@implementation TestView

- (id)initWithFrame:(NSRect)aFrame
{
  if (self = [super initWithFrame:aFrame]) {
    NSOpenGLPixelFormatAttribute attribs[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        (NSOpenGLPixelFormatAttribute)0
    };
    NSOpenGLPixelFormat* pixelFormat = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attribs] autorelease];
    mContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    GLint swapInt = 0;
    [mContext setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    GLint opaque = 1;
    [mContext setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
    [mContext makeCurrentContext];
    [self _initGL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewGlobalFrameDidChangeNotification
                                               object:self];
    CreateDecoder(self, mContext, 1120, 626);
    mStarted = false;
  }
  return self;
}

- (void)dealloc
{
  [self _cleanupGL];
  [mContext release];
  [super dealloc];
  DestroyDecoder();
}

static GLuint
CompileShaders(const char* vertexShader, const char* fragmentShader)
{
  // Create the shaders
  GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
  GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);

  GLint result = GL_FALSE;
  int infoLogLength;

  // Compile Vertex Shader
  glShaderSource(vertexShaderID, 1, &vertexShader , NULL);
  glCompileShader(vertexShaderID);

  // Check Vertex Shader
  glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* vertexShaderErrorMessage = (char*) malloc(infoLogLength+1);
    glGetShaderInfoLog(vertexShaderID, infoLogLength, NULL, vertexShaderErrorMessage);
    printf("%s\n", vertexShaderErrorMessage);
    free(vertexShaderErrorMessage);
  }

  // Compile Fragment Shader
  glShaderSource(fragmentShaderID, 1, &fragmentShader , NULL);
  glCompileShader(fragmentShaderID);

  // Check Fragment Shader
  glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* fragmentShaderErrorMessage = (char*) malloc(infoLogLength+1);
    glGetShaderInfoLog(fragmentShaderID, infoLogLength, NULL, fragmentShaderErrorMessage);
    printf("%s\n", fragmentShaderErrorMessage);
    free(fragmentShaderErrorMessage);
  }

  // Link the program
  GLuint programID = glCreateProgram();
  glAttachShader(programID, vertexShaderID);
  glAttachShader(programID, fragmentShaderID);
  glLinkProgram(programID);

  // Check the program
  glGetProgramiv(programID, GL_LINK_STATUS, &result);
  glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* programErrorMessage = (char*) malloc(infoLogLength+1);
    glGetProgramInfoLog(programID, infoLogLength, NULL, programErrorMessage);
    printf("%s\n", programErrorMessage);
    free(programErrorMessage);
  }

  glDeleteShader(vertexShaderID);
  glDeleteShader(fragmentShaderID);

  return programID;
}

- (void)output:(IOSurfaceRef)surface
{
    dispatch_async(dispatch_get_main_queue(), ^{
        printf("Processing output\n");
        [self upload:surface];
    });
}

- (void)upload:(IOSurfaceRef)surface
{
    GLsizei width = (GLsizei)IOSurfaceGetWidth(surface);
    GLsizei height = (GLsizei)IOSurfaceGetHeight(surface);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTexture);

    CGLError err = CGLTexImageIOSurface2D([mContext CGLContextObj],
                                          GL_TEXTURE_RECTANGLE_ARB, GL_RGB, width, height,
                                          GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE, surface, 0);

    if (err != kCGLNoError) {
        printf("GL error=%d\n", (int)err);
        return;
    }
    [self drawme];
}

- (void)drawme
{
    [mContext setView:self];
    [mContext makeCurrentContext];

    NSSize backingSize = [self convertSizeToBacking:[self bounds].size];
    GLdouble width = backingSize.width;
    GLdouble height = backingSize.height;
    glViewport(0, 0, width, height);

    glClearColor(0.0, 1.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(mProgramID);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, mTexture);
    glUniform1i(mTextureUniform, 0);

    glEnableVertexAttribArray(mPosAttribute);
    glBindBuffer(GL_ARRAY_BUFFER, mVertexbuffer);
    glVertexAttribPointer(
                          mPosAttribute, // The attribute we want to configure
                          2,             // size
                          GL_FLOAT,      // type
                          GL_FALSE,      // normalized?
                          0,             // stride
                          (void*)0       // array buffer offset
                          );

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); // 4 indices starting at 0 -> 2 triangles

    glDisableVertexAttribArray(mPosAttribute);

    [mContext flushBuffer];
}

- (void)_initGL
{
  // Create and compile our GLSL program from the shaders.
  mProgramID = CompileShaders(
    "#version 120\n"
    "// Input vertex data, different for all executions of this shader.\n"
    "attribute vec2 aPos;\n"
    "varying vec2 vPos;\n"
    "void main(){\n"
    "  vPos = aPos;\n"
    "  gl_Position = vec4(aPos.x * 2.0 - 1.0, 1.0 - aPos.y * 2.0, 0.0, 1.0);\n"
    "}\n",

    "#version 120\n"
    "varying vec2 vPos;\n"
    "uniform sampler2DRect uSampler;\n"
    "void main()\n"
    "{\n"
    "  gl_FragColor = texture2DRect(uSampler, vPos * vec2(1120, 626));\n" // <-- ATTENTION I HARDCODED THE TEXTURE SIZE HERE SORRY ABOUT THAT
    "}\n");

  // Create a texture
  glGenTextures(1, &mTexture);
  mTextureUniform = glGetUniformLocation(mProgramID, "uSampler");

  // Get a handle for our buffers
  mPosAttribute = glGetAttribLocation(mProgramID, "aPos");

  static const GLfloat g_vertex_buffer_data[] = {
     0.0f,  0.0f,
     1.0f,  0.0f,
     0.0f,  1.0f,
     1.0f,  1.0f,
  };

  glGenBuffers(1, &mVertexbuffer);
  glBindBuffer(GL_ARRAY_BUFFER, mVertexbuffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(g_vertex_buffer_data), g_vertex_buffer_data, GL_STATIC_DRAW);
}

- (void)_cleanupGL
{
  glDeleteTextures(1, &mTexture);
  glDeleteBuffers(1, &mVertexbuffer);
}

- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
  [mContext update];
}

- (void)drawRect:(NSRect)aRect
{
    [self drawme];
    if (!mStarted) {
        mStarted = true;
        NotifyFrameNeeded();
    }
}

- (BOOL)wantsBestResolutionOpenGLSurface
{
  return YES;
}

@end


@interface TerminateOnClose : NSObject<NSWindowDelegate>
@end

@implementation TerminateOnClose
- (void)windowWillClose:(NSNotification*)notification
{
  [NSApp terminate:self];
}
@end


int main (int argc, char **argv)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  int style = NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
  NSRect contentRect = NSMakeRect(200, 200, 1120, 626);
  NSWindow* window = [[NSWindow alloc] initWithContentRect:contentRect
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];

  NSView* view = [[TestView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)];

  [window setContentView:view];
  [window setDelegate:[[TerminateOnClose alloc] autorelease]];
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:window];

  [NSApp run];

  [pool release];
  
  return 0;
}
