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
            double idle_seconds = idle_steps / 10.0;
            assert(idle_seconds >= 5 * 60 && idle_seconds <= 15 * 60 + 0.2);
            idle_steps = 0;
            turned = false;
            trips++;
        }
        if (gait && strcmp(f.group, inward)) turned = true;
        if (running && !gait) assert(turned && f.dx == 0);
        if (gait) assert(right ? f.dx <= 0 : f.dx >= 0);
        running = gait;
    }
    assert(trips >= 2);
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

static void check_gestures(void) {
    FCPet *pet = fc_create();
    assert(pet);
    fc_sneeze(pet);
    fc_step(pet, 1, false, false, false, false);
    for (int i = 0; i < 8; ++i) {
        FCFrame f = fc_step(pet, 1.05 + i * 0.2, false, false, false, false);
        assert(!strcmp(f.group, "sneeze") && f.frame == i);
    }
    assert(!strcmp(fc_step(pet, 2.62, false, false, false, false).group, "idle"));
    fc_hearts(pet);
    fc_step(pet, 3, false, false, false, false);
    for (int i = 0; i < 11; ++i) {
        FCFrame f = fc_step(pet, 3.05 + i * 0.2, false, false, false, false);
        assert(!strcmp(f.group, "hearts") && f.frame == i);
    }
    assert(!strcmp(fc_step(pet, 5.21, false, false, false, false).group, "idle"));
    fc_dash(pet);
    assert(!strcmp(fc_step(pet, 6, false, false, false, true).group, "idle"));
    fc_hearts(pet);
    assert(!strcmp(fc_step(pet, 7, true, false, false, false).group, "flame"));
    assert(!strcmp(fc_step(pet, 7.1, false, false, false, false).group, "idle"));
    fc_destroy(pet);
}

static void check_run_timing(void) {
    FCPet *pet = fc_create();
    assert(pet);
    double due = fc_dash_remaining(pet);
    assert(due >= 300 && due <= 900);
    fc_step(pet, 0, false, false, false, false);
    fc_step(pet, 15, false, false, false, false);
    assert(fabs(fc_dash_remaining(pet) - (due - 15)) < 0.0001);
    fc_step(pet, 16, true, false, false, false);
    fc_step(pet, 2000, true, false, false, false);
    assert(fabs(fc_dash_remaining(pet) - (due - 15)) < 0.0001);
    fc_step(pet, 2001, false, false, false, false);
    FCFrame due_run = fc_step(pet, 2001 + due, false, false, false, false);
    assert(!strcmp(due_run.group, "right") && due_run.dx == 0);

    for (int side = 0; side < 2; ++side) {
        double now = 4000 + side * 10;
        fc_step(pet, now - 1, true, false, side, false);
        fc_dash(pet);
        FCFrame start = fc_step(pet, now, true, false, side, false);
        assert(!strcmp(start.group, side ? "left" : "right"));
        FCFrame peak = fc_step(pet, now + 1.2, true, false, side, false);
        assert(fabs(peak.dx - (side ? -44 : 44)) < 0.01);
        FCFrame back = fc_step(pet, now + 2, true, false, side, false);
        assert(!strcmp(back.group, side ? "right" : "left") && fabs(back.dx) < 16);
        FCFrame done = fc_step(pet, now + 2.5, true, false, side, false);
        assert(!strcmp(done.group, "flame") && done.dx == 0);
    }
    fc_dash(pet);
    assert(!strcmp(fc_step(pet, 5000, true, false, false, true).group, "flame"));
    fc_dash(pet);
    assert(!strcmp(fc_step(pet, 5001, true, true, false, false).group, "tears"));
    fc_destroy(pet);
}

int main(void) {
    check_run_timing();
    check_gestures();
    simulate(false);
    simulate(true);
    puts("Gestures, work/error priority, short runs from both sides and reduced motion passed");
}
