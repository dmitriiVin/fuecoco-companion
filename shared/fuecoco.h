#pragma once

#include <stdbool.h>

typedef struct FCPet FCPet;
typedef struct {
    const char *group;
    int frame;
    double dx, dy;
} FCFrame;

FCPet *fc_create(void);
void fc_destroy(FCPet *pet);
void fc_wave(FCPet *pet);
void fc_dash(FCPet *pet);
double fc_dash_remaining(const FCPet *pet);
void fc_sneeze(FCPet *pet);
void fc_hearts(FCPet *pet);
FCFrame fc_step(FCPet *pet, double monotonic, bool building, bool failed, bool right_corner, bool reduced);

typedef struct {
    bool building;
    bool failed;
} FCBuild;
FCBuild fc_sample_build(void);
