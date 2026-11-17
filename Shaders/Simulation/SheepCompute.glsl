#[compute]
#version 450

layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) readonly buffer Inputs { float f[]; };
layout(set = 0, binding = 1, std430) readonly buffer Indices { int ix[]; };
layout(set = 0, binding = 2, std430) buffer Results { float out_data[]; };
layout(push_constant, std430) uniform Pass { int stage; } pass_data;

// Read packed animal vectors after the 32-float configuration header.
// e.g. field = 2 selects velocity, while field = 4 selects cached separation.
vec2 animal_vec(int row, int field) {
	int p = 32 + field * ix[2] + row * 2;
	return vec2(f[p], f[p + 1]);
}

float animal_value(int row, int field) {
	if (field == 14) return float(ix[ix[24] + row]);
	if (field == 15) return float(ix[ix[25] + row]);
	return f[32 + field * ix[2] + row];
}

vec2 safe_normalize(vec2 v) {
	float d = length(v);
	return d > 0.0 ? v / d : vec2(0.0);
}

vec2 limit_vector(vec2 v, float maximum) {
	float d = length(v);
	return d > maximum && d > 0.0 ? v * (maximum / d) : v;
}

void store_vec(int p, vec2 v) {
	out_data[p] = v.x;
	out_data[p + 1] = v.y;
}

int cell_at(vec2 p) {
	ivec2 c = clamp(ivec2(floor(p / f[0])), ivec2(0), ivec2(ix[0] - 1, ix[1] - 1));
	return c.y * ix[0] + c.x;
}

vec2 cell_sum(int cell, int component) {
	int p = 32 + ix[2] * 14 + component * ix[0] * ix[1] + cell * 2;
	return vec2(f[p], f[p + 1]);
}

void aggregate(int index) {
	if (index >= ix[6]) return;

	int cell = ix[ix[19] + index];
	ivec2 c = ivec2(cell % ix[0], cell / ix[0]);
	for (int kind = 0; kind < 2; ++kind) {
		vec2 sum = vec2(0.0);
		int count = 0;
		for (int n = 0; n < ix[17 + kind]; ++n) {
			int o = ix[15 + kind] + n * 2;
			ivec2 q = c + ivec2(ix[o], ix[o + 1]);
			if (any(lessThan(q, ivec2(0))) || q.x >= ix[0] || q.y >= ix[1]) continue;
			int neighbor = q.y * ix[0] + q.x;
			count += ix[ix[14] + neighbor * 3];
			sum += cell_sum(neighbor, kind * 2);
		}
		int p = index * 8 + kind * 4;
		out_data[p] = float(count);
		store_vec(p + 1, sum);
	}
}

void pressure_node(int index) {
	if (index >= ix[7]) return;

	int node = ix[ix[21] + index];
	vec2 point = vec2(node % (ix[0] + 1), node / (ix[0] + 1)) * f[0];
	int p = ix[6] * 8 + index * 6;
	for (int kind = 0; kind < 2; ++kind) {
		vec2 sum = vec2(0.0);
		int pairs = 0;
		float radius = f[4 + kind];
		if (radius > 0.0) {
			for (int n = 0; n < ix[4 + kind]; ++n) {
				int row = ix[ix[12 + kind] + n];
				vec2 offset = point - animal_vec(row, 0);
				float squared = dot(offset, offset);
				if (squared > radius * radius) continue;
				float d = sqrt(squared);
				float multiplier = kind == 0 && animal_value(row, 15) > 0.0 ? f[6] : 1.0;
				sum += (d > 0.0 ? offset / d : vec2(0.0)) * ((1.0 - d / radius) * multiplier);
				pairs++;
			}
		}
		store_vec(p + kind * 2, sum);
		out_data[p + 4 + kind] = float(pairs);
	}
}

vec2 node_value(int node, int kind) {
	int index = ix[ix[22] + node];
	if (index < 0) return vec2(0.0);
	int p = ix[6] * 8 + index * 6 + kind * 2;
	return vec2(out_data[p], out_data[p + 1]);
}

vec2 sample_field(vec2 point, int kind) {
	vec2 coordinate = point / f[0];
	ivec2 c = clamp(ivec2(floor(coordinate)), ivec2(0), ivec2(ix[0] - 1, ix[1] - 1));
	vec2 fraction = clamp(coordinate - vec2(c), vec2(0.0), vec2(1.0));
	int node = c.y * (ix[0] + 1) + c.x;
	return mix(mix(node_value(node, kind), node_value(node + 1, kind), fraction.x),
		mix(node_value(node + ix[0] + 1, kind), node_value(node + ix[0] + 2, kind), fraction.x), fraction.y);
}

void sheep(int index) {
	if (index >= ix[3]) return;

	// 1) Read shared flock aggregates and refresh local separation only when due.
	int row = ix[ix[11] + index];
	vec2 point = animal_vec(row, 0);
	int cell = ix[ix[10] + row];
	int aggregate_index = ix[ix[20] + cell] * 8;
	int count = int(out_data[aggregate_index]) - 1;
	int aligned = int(out_data[aggregate_index + 4]) - 1;
	vec2 center = count > 0 ? (vec2(out_data[aggregate_index + 1], out_data[aggregate_index + 2]) - point) / float(count) : point;
	vec2 alignment = aligned > 0 ? (vec2(out_data[aggregate_index + 5], out_data[aggregate_index + 6]) - animal_vec(row, 2)) / float(aligned) : vec2(0.0);
	bool refresh = animal_value(row, 14) == 0.0 || animal_value(row, 7) <= 0.0;
	vec2 separation = animal_vec(row, 4);
	if (refresh) {
		separation = vec2(0.0);
		ivec2 first = max(ivec2(floor((point - f[1]) / f[0])), ivec2(0));
		ivec2 last = min(ivec2(floor((point + f[1]) / f[0])), ivec2(ix[0] - 1, ix[1] - 1));
		for (int y = first.y; y <= last.y; ++y) {
			for (int x = first.x; x <= last.x; ++x) {
				int bucket = (y * ix[0] + x) * 3;
				for (int n = ix[ix[8] + bucket]; n < ix[ix[8] + bucket + 1]; ++n) {
					int other = ix[ix[9] + n];
					if (other == row) continue;
					vec2 offset = point - animal_vec(other, 0);
					float d = length(offset);
					if (f[1] <= 0.0 || d >= f[1]) continue;
					vec2 direction = d >= 0.001 ? safe_normalize(offset) : (ix[ix[23] + row] < ix[ix[23] + other] ? vec2(1, 0) : vec2(-1, 0));
					separation += direction * (1.0 - d / f[1]);
				}
			}
		}
	}

	// 2) Use shared pressure in dense cells while retaining exact source-radius checks.
	vec2 threat = vec2(0.0);
	vec2 dog = vec2(0.0);
	float strength = 0.0;
	bool use_shared = ix[ix[14] + cell * 3] >= 4;
	for (int kind = 0; kind < 2; ++kind) {
		float radius = f[4 + kind];
		vec2 force = vec2(0.0);
		bool affected = false;
		if (radius > 0.0) {
			for (int n = 0; n < ix[4 + kind]; ++n) {
				int source = ix[ix[12 + kind] + n];
				vec2 offset = point - animal_vec(source, 0);
				float squared = dot(offset, offset);
				if (squared > radius * radius) continue;
				float d = sqrt(squared);
				float multiplier = kind == 0 && animal_value(source, 15) > 0.0 ? f[6] : 1.0;
				float value = (1.0 - d / radius) * multiplier;
				if (kind == 0) strength = min(1.0, strength + value);
				if (!use_shared) force += (d > 0.0 ? offset / d : vec2(0.0)) * value;
				affected = true;
			}
		}
		if (use_shared && affected) force = sample_field(point, kind);
		if (kind == 0) threat = strength > 0.0 ? force : vec2(0.0);
		else dog = force;
	}

	// 3) Blend danger, dog pressure, flock motion and wandering into a bounded intent.
	float panic = animal_value(row, 6);
	float danger = max(strength, panic);
	vec2 escape = limit_vector(threat + safe_normalize(point - animal_vec(row, 8)) * panic, 1.0);
	if (danger > 0.0 && all(lessThan(abs(escape), vec2(0.00001)))) escape = animal_vec(row, 12) * danger;
	float speed = mix(mix(f[7] * f[9], f[7], min(1.0, length(dog))), f[8], danger);
	vec2 flock = alignment * f[12] + (count > 0 ? safe_normalize(center - point) : vec2(0.0)) * f[7] * f[13];
	vec2 steering = escape * speed * f[14] + dog * speed * f[15] * (1.0 - danger);
	steering += flock * mix(1.0, 0.25, danger);
	steering += safe_normalize(animal_vec(row, 10) - point) * speed * f[10] * (1.0 - danger);
	steering += separation * f[7] * f[11];

	int p = ix[6] * 8 + ix[7] * 6 + index * 16;
	store_vec(p, separation);
	store_vec(p + 2, center);
	store_vec(p + 4, alignment);
	store_vec(p + 6, threat);
	out_data[p + 8] = strength;
	store_vec(p + 9, dog);
	store_vec(p + 11, limit_vector(steering, speed));
	out_data[p + 13] = speed;
	out_data[p + 14] = float(count);
	out_data[p + 15] = refresh ? 1.0 : 0.0;
}

void main() {
	// Dispatch aggregates, pressure nodes and sheep in separate passes with host-side barriers.
	// e.g. stage 2 reads the aggregate and pressure outputs produced by stages 0 and 1.
	int index = int(gl_GlobalInvocationID.x);
	if (pass_data.stage == 0) aggregate(index);
	else if (pass_data.stage == 1) pressure_node(index);
	else sheep(index);
}
