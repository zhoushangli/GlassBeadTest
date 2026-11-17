#[compute]
#version 450
#extension GL_ARB_gpu_shader_fp64 : require

layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) readonly buffer Input { double values[]; };
layout(set = 0, binding = 1, std430) readonly buffer Indices { int indices[]; };
layout(set = 0, binding = 2, std430) writeonly buffer Output { double result[]; };
layout(set = 0, binding = 3, std430) readonly buffer Configuration { double config[]; };

void main() {
	int row = int(gl_GlobalInvocationID.x);
	int count = indices[0];
	if (row >= count) {
		return;
	}
	result[row] = values[row] - config[0];
	result[count + row] = values[count + row] - config[0];
	double panic = values[count * 2 + row];
	if (indices[2 + row] == 0) {
		panic = config[1] > 0.0 ? max(0.0, panic - config[0] / config[1]) : 0.0;
	}
	result[count * 2 + row] = panic;
}
