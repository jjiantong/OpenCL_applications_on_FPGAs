#include "HardwareMandelbrot.h"

using namespace aocl_utils;

extern unsigned int theWidth;
extern unsigned int theHeight;

// ACL runtime configuration
static unsigned numDevices = 0;
static cl_platform_id thePlatform;
static scoped_array<cl_device_id> theDevices;
static cl_context theContext;
static scoped_array<cl_command_queue> theQueues;
static scoped_array<cl_kernel> theKernels;
static cl_program theProgram;
static cl_int theStatus;
static scoped_array<unsigned> rowsPerDevice;

static scoped_array<cl_mem> thePixelData;
static unsigned int thePixelDataWidth = 0;
static unsigned int thePixelDataHeight = 0;

static cl_mem theHardColorTable = 0;
static unsigned int theHardColorTableSize = 0;

// Reset the frame buffer size
int hardwareSetFrameBufferSize()
{
  if(thePixelDataWidth != theWidth &&
    thePixelDataHeight != theHeight)
  {
    // Set new sizes
    thePixelDataWidth = theWidth;
    thePixelDataHeight = theHeight;

    // If the buffer already exists release it
    if(thePixelData) {
      for(unsigned i = 0; i < numDevices; ++i) {
        clReleaseMemObject(thePixelData[i]);
      }
    }

    // Distribute rows evenly across all devices.
    rowsPerDevice.reset(numDevices);
    for(unsigned i = 0; i < numDevices; ++i) {
      rowsPerDevice[i] = thePixelDataHeight / numDevices;
      if(i < (thePixelDataHeight % numDevices)) { // for extra rows
        rowsPerDevice[i]++;
      }
    }

    thePixelData.reset(numDevices);
    for(unsigned i = 0; i < numDevices; ++i) {
      // create the input pixel data buffer
      thePixelData[i] = clCreateBuffer(theContext, CL_MEM_WRITE_ONLY, 
          thePixelDataWidth*rowsPerDevice[i]*sizeof(unsigned int), NULL, &theStatus);
      checkError(theStatus, "Failed to create input pixel buffer");
    }
  }

  // Return success
  return 0;
}

// get the platform and device, and create the context, program, and kernels
int hardwareInitialize()
{
  if(!setCwdToExeDir()) 
  {
    return -1;
  }

  // Set up the platform
  thePlatform = findPlatform("Intel(R) FPGA");
  if(thePlatform == NULL)
  {
    printf("Found no platforms!\n");
    hardwareRelease();
    return -1;
  }

  // Set up the device(s)
  theDevices.reset(getDevices(thePlatform, CL_DEVICE_TYPE_ALL, &numDevices));

  // Print the name of the platform being used
  printf("Using platform: %s\n", getPlatformName(thePlatform).c_str());
  printf("Using %d devices:\n", numDevices);
  for(unsigned i = 0; i < numDevices; ++i) {
    printf("  %s\n", getDeviceName(theDevices[i]).c_str());
  }

  // Create a context
  theContext = clCreateContext(0, numDevices, theDevices, &oclContextCallback, NULL, &theStatus);
  checkError(theStatus, "Failed to create context");

  // Create command queues
  theQueues.reset(numDevices);
  for(unsigned i = 0; i < numDevices; ++i) {
    theQueues[i] = clCreateCommandQueue(theContext, theDevices[i], CL_QUEUE_PROFILING_ENABLE, &theStatus);
    checkError(theStatus, "Failed to create command queue");
  }

  // the name of the kernel we are going to load
  const char *kernel_name = "hw_mandelbrot_frame";
  


  // Create the program using the binary aocx file
  std::string binary_file = getBoardBinaryFile("ul40", theDevices[0]);
  printf("Using AOCX: %s\n", binary_file.c_str());
  theProgram = createProgramFromBinary(theContext, binary_file.c_str(), theDevices, numDevices);



  // Create the kernels
  theKernels.reset(numDevices);
  for(unsigned i = 0; i < numDevices; ++i) {
    theKernels[i] = clCreateKernel(theProgram, kernel_name, &theStatus);
    checkError(theStatus, "Failed to create kernel");
  }

  // Return success
  return 0;
}

// Set the color table
int hardwareSetColorTable(
  unsigned int* aColorTable,
  unsigned int aColorTableSize)
{
  // If the color table is a different size than before
  if(theHardColorTableSize != aColorTableSize)
  {
    // Set new table size
    theHardColorTableSize = aColorTableSize;

    // Free old table
    if(theHardColorTable) clReleaseMemObject(theHardColorTable);

    // Create new table
    theHardColorTable = clCreateBuffer(theContext, CL_MEM_READ_ONLY, aColorTableSize*sizeof(unsigned int), NULL, &theStatus);
    checkError(theStatus, "Failed to create color table buffer");
  }

  // Write the color table data to the device on the current queue
  theStatus = clEnqueueWriteBuffer(theQueues[0], theHardColorTable, CL_TRUE, 0, aColorTableSize*sizeof(unsigned int), aColorTable, 0, NULL, NULL);
  checkError(theStatus, "Failed to write to color table buffer");

  // Return success
  return 0;
}

// calculate the current frame using Altera hardware
int hardwareCalculateFrame(
  double aStartX,
  double aStartY,
  double aScale,
  unsigned int* aFrameBuffer)
{
  // Make sure width and height match up
  hardwareSetFrameBufferSize();

  unsigned rowOffset = 0;
  
  
  
  scoped_array<cl_event> kernel_event(numDevices);

  const double start_time = getCurrentTimestamp();
  
  

  
  
  for(unsigned i = 0; i < numDevices; rowOffset += rowsPerDevice[i++])
  {
    // Create ND range size
    size_t globalSize[2] = {thePixelDataWidth, rowsPerDevice[i]};

    // Set the arguments
    unsigned argi = 0;
    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_double), (void*)&aStartX);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    const double offsetedStartY = aStartY - rowOffset * aScale;
    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_double), (void*)&offsetedStartY);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_double), (void*)&aScale);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_uint), (void*)&theHardColorTableSize);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_mem), (void*)&thePixelData[i]);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_mem), (void*)&theHardColorTable);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);

    theStatus = clSetKernelArg(theKernels[i], argi++, sizeof(cl_uint), (void*)&theWidth);
    checkError(theStatus, "Failed to set kernel argument %d", argi - 1);




    // Launch kernel
    theStatus = clEnqueueNDRangeKernel(theQueues[i], theKernels[i], 2, NULL, globalSize, NULL, 0, NULL, &kernel_event[i]);
    checkError(theStatus, "Failed to enqueue kernel");
  }




  clWaitForEvents(numDevices, kernel_event);

  const double end_time = getCurrentTimestamp();

  const double kernel_time = end_time - start_time;

  printf("\nKernel time: %0.3f ms\n",kernel_time * 1e3);

  for(unsigned i = 0; i < numDevices; rowOffset += rowsPerDevice[i++]) {
    cl_ulong time_ns = getStartEndTime(kernel_event[i]);
    printf("Kernel Time (using event): %0.3f ms\n", double(time_ns) * 1e-6);
  }


  for(unsigned i = 0; i < numDevices; rowOffset += rowsPerDevice[i++]) {
    clReleaseEvent(kernel_event[i]);
  }




  rowOffset = 0;
  for(unsigned i = 0; i < numDevices; rowOffset += rowsPerDevice[i++])
  {
    // Read the output
    theStatus = clEnqueueReadBuffer(theQueues[i], thePixelData[i], CL_TRUE, 0, thePixelDataWidth*rowsPerDevice[i]*sizeof(unsigned int), &aFrameBuffer[rowOffset * theWidth], 0, NULL, NULL);
    checkError(theStatus, "Failed to read output");
  }

  // Return success
  return 0;
}


// free memory allocated by the program
int hardwareRelease()
{
  // Release all created objects
  for(unsigned i = 0; i < numDevices; ++i)
  {
    if(theKernels && theKernels[i]) 
      clReleaseKernel(theKernels[i]);
    if(theQueues && theQueues[i]) 
      clReleaseCommandQueue(theQueues[i]);
    if(thePixelData && thePixelData[i]) 
      clReleaseMemObject(thePixelData[i]);
  }
  if(theProgram) 
    clReleaseProgram(theProgram);
  if(theContext) 
    clReleaseContext(theContext);
  if(theHardColorTable) 
    clReleaseMemObject(theHardColorTable);

  // Return success
  return 0;
}

// Called by aocl_utils::checkError
void cleanup() {
  hardwareRelease();
}

