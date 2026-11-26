#include "../shared/fuecoco.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static void simulate(bool right) {
    FCPet *pet = fc_create();
    assert(pet);
    int trips = 0, idle_steps = 0;
    bool running = false, turned = false;
    const char *inward = right ? "left" : "right";
    for (int i = 0; i < 50000; ++i) {
        FCFrame f = fc_step(pet, i / 10.0, false, false, right, false);
        assert(fabs(f.dx) <= 44 && f.dy >= 0 && f.dy <= 12);
        if (!strcmp(f.group, "idle")) idle_steps++;
        bool gait = !strcmp(f.group, "left") || !strcmp(f.group, "right");
        if (gait && !running) {
            assert(!strcmp(f.group, inward) && fabs(f.dx) < 0.1);
            assert(idle_steps >= 20990 && idle_steps <= 39020);
            idle_steps = 0;
            turned = false;
            trips++;
        }
        if (gait && strcmp(f.group, inward)) turned = true;
        if (running && !gait) assert(turned && f.dx == 0);
        if (gait) assert(right ? f.dx <= 0 : f.dx >= 0);
        running = gait;
    }
    assert(trips);
    fc_wave(pet);
    FCFrame wave = fc_step(pet, 5001, false, false, right, false);
    assert(!strcmp(wave.group, "wave"));
    FCFrame fire = fc_step(pet, 5001.2, true, false, right, false);
    assert(!strcmp(fire.group, "flame") && fire.dx == 0);
    assert(!strcmp(fc_step(pet, 5001.3, true, true, right, false).group, "tears"));
    assert(!strcmp(fc_step(pet, 5001.4, false, false, right, false).group, "idle"));
    for (int i = 0; i < 50000; ++i) {
        FCFrame f = fc_step(pet, 5010 + i / 10.0, false, false, right, true);
        assert(f.dx == 0 && f.dy == 0);
    }
    fc_destroy(pet);
}

int main(void) {
    simulate(false);
    simulate(true);
    puts("Wave, work/error priority, short runs from both sides and reduced motion passed");
}
