#[compute]
#version 450

layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) readonly buffer Input { float values[]; };
layout(set = 0, binding = 1, std430) readonly buffer Indices { int indices[]; };
layout(set = 0, binding = 2, std430) writeonly buffer Output { float result[]; };
layout(set = 0, binding = 3, std430) readonly buffer Configuration { float config[]; };

vec2 vector_at(int column, int row, int count) {
	int offset = column * count * 2 + row * 2;
	return vec2(values[offset], values[offset + 1]);
}

void store_vector(int column, int row, int count, vec2 value) {
	int offset = column * count * 2 + row * 2;
	result[offset] = value.x;
	result[offset + 1] = value.y;
}

vec2 limited(vec2 value, float maximum) {
	float magnitude = length(value);
	return magnitude > 0.0 && magnitude > maximum ? value * (maximum / magnitude) : value;
}

void main() {
	int row = int(gl_GlobalInvocationID.x);
	int count = indices[0];
	if (row >= count) {
		return;
	}
	float delta = config[0];

	vec2 previous = vector_at(0, row, count);
	vec2 velocity = vector_at(1, row, count);
	vec2 facing = vector_at(2, row, count);
	vec2 desired = vector_at(3, row, count);
	float speed = values[count * 12 + row];
	int intent = indices[2 + row];
	int kind = indices[2 + count + row];
	vec2 lower = vec2(config[2], config[3]);
	vec2 upper = vec2(config[4], config[5]);
	if (intent == 1) {
		vec2 difference = vector_at(4, row, count) - previous;
		float distance = length(difference);
		desired = distance > 0.0 ? difference / distance * min(speed, distance / max(delta, 0.00001)) : vec2(0.0);
	} else if (intent == 2) {
		vec2 boundary = max(lower + 40.0 - previous, vec2(0.0)) - max(previous - upper + 40.0, vec2(0.0));
		vec2 steering = limited(desired + boundary / 40.0 * speed * 2.0, speed);
		velocity = mix(velocity, steering, min(1.0, config[1] * delta));
	}
	vec2 separation = kind == 0 ? vec2(0.0) : vector_at(5, row, count) * config[8 + kind];
	velocity = limited((intent == 2 ? velocity : desired) + separation, speed);
	vec2 position = clamp(previous + velocity * delta, lower, upper);
	velocity = (position - previous) / max(delta, 0.00001);
	if (abs(velocity.x) >= 0.00001 || abs(velocity.y) >= 0.00001) {
		facing = normalize(velocity);
	}
	store_vector(0, row, count, position);
	store_vector(1, row, count, velocity);
	store_vector(2, row, count, facing);
	store_vector(3, row, count, desired);
}
