#define _OPENCL_COMPILER_

#define MAX 6000

#include "support/common.h"

// OpenCL baseline kernel ------------------------------------------------------------------------------------------
// Generate model on GPU side
int gen_model_param(int x1, int y1, int vx1, int vy1, int x2, int y2, int vx2, int vy2, float *model_param) {
    float temp;
    temp = (float)((vx1 * (vx1 - (2 * vx2))) + (vx2 * vx2) + (vy1 * vy1) - (vy2 * ((2 * vy1) - vy2)));
    if(temp == 0) { // Check to prevent division by zero
        return (0);
    }
    model_param[0] = (((vx1 * ((-vx2 * x1) + (vx1 * x2) - (vx2 * x2) + (vy2 * y1) - (vy2 * y2))) +
                          (vy1 * ((-vy2 * x1) + (vy1 * x2) - (vy2 * x2) - (vx2 * y1) + (vx2 * y2))) +
                          (x1 * ((vy2 * vy2) + (vx2 * vx2)))) /
                      temp);
    model_param[1] = (((vx2 * ((vy1 * x1) - (vy1 * x2) - (vx1 * y1) + (vx2 * y1) - (vx1 * y2))) +
                          (vy2 * ((-vx1 * x1) + (vx1 * x2) - (vy1 * y1) + (vy2 * y1) - (vy1 * y2))) +
                          (y2 * ((vx1 * vx1) + (vy1 * vy1)))) /
                      temp);

    temp = (float)((x1 * (x1 - (2 * x2))) + (x2 * x2) + (y1 * (y1 - (2 * y2))) + (y2 * y2));
    if(temp == 0) { // Check to prevent division by zero
        return (0);
    }
    model_param[2] = ((((x1 - x2) * (vx1 - vx2)) + ((y1 - y2) * (vy1 - vy2))) / temp);
    model_param[3] = ((((x1 - x2) * (vy1 - vy2)) + ((y2 - y1) * (vx1 - vx2))) / temp);
    return (1);
}


	channel float4 c_model[4];
	channel int c_count[4];

__kernel void RANSAC_model( int n_tasks, __global flowvector *restrict flowvectors,
    __global int *restrict random_numbers) {

	float model_param[4];

    for(int iter = 0; iter < n_tasks; iter++) {

        model_param[0] = 0;
		model_param[1] = 0;
		model_param[2] = 0;
		model_param[3] = 0;

        int        rand_num = random_numbers[iter * 2 + 0];
        flowvector fv[2];
        fv[0]    = flowvectors[rand_num];
        rand_num = random_numbers[iter * 2 + 1];
        fv[1]    = flowvectors[rand_num];

        int ret = 0;
        int vx1 = fv[0].vx - fv[0].x;
        int vy1 = fv[0].vy - fv[0].y;
        int vx2 = fv[1].vx - fv[1].x;
        int vy2 = fv[1].vy - fv[1].y;

        ret = gen_model_param(fv[0].x, fv[0].y, vx1, vy1, fv[1].x, fv[1].y, vx2, vy2, model_param);
        if(ret == 0)
			model_param[0] = -2011;

		float4 model_float4;
		model_float4.s0 = model_param[0];
		model_float4.s1 = model_param[1];
		model_float4.s2 = model_param[2];
		model_float4.s3 = model_param[3];

		if(iter % 4 == 0)
			write_channel_altera(c_model[0], model_float4);
		else if (iter % 4 == 1)
			write_channel_altera(c_model[1], model_float4);
		else if (iter % 4 == 2)
			write_channel_altera(c_model[2], model_float4);
		else
			write_channel_altera(c_model[3], model_float4);
	}
}



__kernel void RANSAC_threshold_0(int flowvector_count, int error_threshold,
    int n_tasks, __global flowvector *restrict flowvectors) {

    float vx_error, vy_error;
    int   outlier_local_count = 0;

	float model_param[4];

    for(int iter = 0; iter < n_tasks; iter += 4) {

		float4 model_float4 = read_channel_altera(c_model[0]);
		model_param[0] = model_float4.s0;
		model_param[1] = model_float4.s1;
		model_param[2] = model_float4.s2;
		model_param[3] = model_float4.s3;

        if(model_param[0] == -2011)
			outlier_local_count = MAX;

		else{

			outlier_local_count = 0;

			for(int i = 0; i < flowvector_count; i++) {
				flowvector fvreg = flowvectors[i]; // x, y, vx, vy
				vx_error         = fvreg.x + ((int)((fvreg.x - model_param[0]) * model_param[2]) -
                                     (int)((fvreg.y - model_param[1]) * model_param[3])) -
						fvreg.vx;
				vy_error = fvreg.y + ((int)((fvreg.y - model_param[1]) * model_param[2]) +
                                     (int)((fvreg.x - model_param[0]) * model_param[3])) -
						fvreg.vy;
				if((fabs(vx_error) >= error_threshold) || (fabs(vy_error) >= error_threshold)) {
					outlier_local_count++;
				}
			}
		}

		write_channel_altera(c_count[0], outlier_local_count);    
    }
}


__kernel void RANSAC_threshold_1(int flowvector_count, int error_threshold,
    int n_tasks, __global flowvector *restrict flowvectors) {

    float vx_error, vy_error;
    int   outlier_local_count = 0;

	float model_param[4];

    for(int iter = 1; iter < n_tasks; iter += 4) {

		float4 model_float4 = read_channel_altera(c_model[1]);
		model_param[0] = model_float4.s0;
		model_param[1] = model_float4.s1;
		model_param[2] = model_float4.s2;
		model_param[3] = model_float4.s3;

        if(model_param[0] == -2011)
			outlier_local_count = MAX;

		else{

			outlier_local_count = 0;

			for(int i = 0; i < flowvector_count; i++) {
				flowvector fvreg = flowvectors[i]; // x, y, vx, vy
				vx_error         = fvreg.x + ((int)((fvreg.x - model_param[0]) * model_param[2]) -
                                     (int)((fvreg.y - model_param[1]) * model_param[3])) -
						fvreg.vx;
				vy_error = fvreg.y + ((int)((fvreg.y - model_param[1]) * model_param[2]) +
                                     (int)((fvreg.x - model_param[0]) * model_param[3])) -
						fvreg.vy;
				if((fabs(vx_error) >= error_threshold) || (fabs(vy_error) >= error_threshold)) {
					outlier_local_count++;
				}
			}
		}

		write_channel_altera(c_count[1], outlier_local_count);    
    }
}


__kernel void RANSAC_threshold_2(int flowvector_count, int error_threshold,
    int n_tasks, __global flowvector *restrict flowvectors) {

    float vx_error, vy_error;
    int   outlier_local_count = 0;

	float model_param[4];

    for(int iter = 2; iter < n_tasks; iter += 4) {

		float4 model_float4 = read_channel_altera(c_model[2]);
		model_param[0] = model_float4.s0;
		model_param[1] = model_float4.s1;
		model_param[2] = model_float4.s2;
		model_param[3] = model_float4.s3;

        if(model_param[0] == -2011)
			outlier_local_count = MAX;

		else{

			outlier_local_count = 0;

			for(int i = 0; i < flowvector_count; i++) {
				flowvector fvreg = flowvectors[i]; // x, y, vx, vy
				vx_error         = fvreg.x + ((int)((fvreg.x - model_param[0]) * model_param[2]) -
                                     (int)((fvreg.y - model_param[1]) * model_param[3])) -
						fvreg.vx;
				vy_error = fvreg.y + ((int)((fvreg.y - model_param[1]) * model_param[2]) +
                                     (int)((fvreg.x - model_param[0]) * model_param[3])) -
						fvreg.vy;
				if((fabs(vx_error) >= error_threshold) || (fabs(vy_error) >= error_threshold)) {
					outlier_local_count++;
				}
			}
		}

		write_channel_altera(c_count[2], outlier_local_count);    
    }
}


__kernel void RANSAC_threshold_3(int flowvector_count, int error_threshold,
    int n_tasks, __global flowvector *restrict flowvectors) {

    float vx_error, vy_error;
    int   outlier_local_count = 0;

	float model_param[4];

    for(int iter = 3; iter < n_tasks; iter += 4) {

		float4 model_float4 = read_channel_altera(c_model[3]);
		model_param[0] = model_float4.s0;
		model_param[1] = model_float4.s1;
		model_param[2] = model_float4.s2;
		model_param[3] = model_float4.s3;

        if(model_param[0] == -2011)
			outlier_local_count = MAX;

		else{

			outlier_local_count = 0;

			for(int i = 0; i < flowvector_count; i++) {
				flowvector fvreg = flowvectors[i]; // x, y, vx, vy
				vx_error         = fvreg.x + ((int)((fvreg.x - model_param[0]) * model_param[2]) -
                                     (int)((fvreg.y - model_param[1]) * model_param[3])) -
						fvreg.vx;
				vy_error = fvreg.y + ((int)((fvreg.y - model_param[1]) * model_param[2]) +
                                     (int)((fvreg.x - model_param[0]) * model_param[3])) -
						fvreg.vy;
				if((fabs(vx_error) >= error_threshold) || (fabs(vy_error) >= error_threshold)) {
					outlier_local_count++;
				}
			}
		}

		write_channel_altera(c_count[3], outlier_local_count);    
    }
}


__kernel void RANSAC_out(int flowvector_count, float convergence_threshold,
    int n_tasks,
    __global int *restrict model_candidate, __global int *restrict outliers_candidate, 
    __global int *g_out_id ) {

	int index = 0;
    for(int iter = 0; iter < n_tasks; iter += 4) {

		int outlier_count_0 = read_channel_altera(c_count[0]);
		int outlier_count_1 = read_channel_altera(c_count[1]);
		int outlier_count_2 = read_channel_altera(c_count[2]);
		int outlier_count_3 = read_channel_altera(c_count[3]);

		if(outlier_count_0 < flowvector_count * convergence_threshold) {
			outliers_candidate[index] = outlier_count_0;
			model_candidate[index] = iter;
			index ++;
        }    

		if(outlier_count_1 < flowvector_count * convergence_threshold) {
			outliers_candidate[index] = outlier_count_1;
			model_candidate[index] = iter + 1;
			index ++;
        }  

		if(outlier_count_2 < flowvector_count * convergence_threshold) {
			outliers_candidate[index] = outlier_count_2;
			model_candidate[index] = iter + 2;
			index ++;
        }    

		if(outlier_count_3 < flowvector_count * convergence_threshold) {
			outliers_candidate[index] = outlier_count_3;
			model_candidate[index] = iter + 3;
			index ++;
        }        
    }
	g_out_id[0] = index; 
}
