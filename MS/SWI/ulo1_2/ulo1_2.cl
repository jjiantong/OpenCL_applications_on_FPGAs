
// Define the color black as 0
#define BLACK 0x00000000

// Mandelbrot set: zn+1 = zn^2 + c;

__kernel 

void hw_mandelbrot_frame (
							const double x0,
							const double y0,
							const double stepSize,
							const unsigned int maxIterations,
							__global unsigned int *restrict framebuffer,
							__constant const unsigned int *restrict colorLUT,
							const unsigned int windowWidth)
{
	for (int windowPosX = 0; windowPosX < 800; windowPosX ++){
		#pragma unroll 2
		for(int windowPosY = 0; windowPosY < 640; windowPosY ++){
		
			const double stepPosX = x0 + (windowPosX * stepSize);
			const double stepPosY = y0 - (windowPosY * stepSize);

			double x = 0.0;
			double y = 0.0;
			double xSqr = 0.0;
			double ySqr = 0.0;
			unsigned int iterations = 0;

			while (	xSqr + ySqr < 4.0 && iterations < maxIterations){
				xSqr = x*x;
				ySqr = y*y;

				y = 2*x*y + stepPosY;
				x = xSqr - ySqr + stepPosX;

				iterations++;
			}

			// Output black if we never finished, and a color from the look up table otherwise
			framebuffer[windowWidth * windowPosY + windowPosX] = (iterations == maxIterations)? BLACK : colorLUT[iterations];
		}	
	}	
}
