#include "fuecoco.h"
#include <math.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

enum Pose { IDLE, FIRE, CRY, SLEEP, HEART, TONGUE, SPARKLE, EMBER, WAVE, HOP, LOOK, DASH, SNEEZE };
enum { DASH_MIN_SECONDS = 5 * 60, DASH_MAX_SECONDS = 15 * 60 };
struct FCPet {
    enum Pose pose;
    double started, last_step, until_rare, until_dash;
    enum Pose requested;
    bool manual_dash;
};

static double delay(int minimum, int maximum) {
    return minimum + (maximum - minimum) * (double)rand() / RAND_MAX;
}

FCPet *fc_create(void) {
    static bool seeded;
    if (!seeded) { srand((unsigned)time(NULL) ^ (unsigned)getpid()); seeded = true; }
    FCPet *pet = calloc(1, sizeof(*pet));
    if (pet) {
        pet->last_step = -1;
        pet->until_rare = delay(55, 115);
        pet->until_dash = delay(DASH_MIN_SECONDS, DASH_MAX_SECONDS);
    }
    return pet;
}
void fc_destroy(FCPet *pet) { free(pet); }
void fc_wave(FCPet *pet) { pet->requested = WAVE; }
void fc_dash(FCPet *pet) { pet->requested = DASH; }
double fc_dash_remaining(const FCPet *pet) { return fmax(0, pet->until_dash); }
void fc_sneeze(FCPet *pet) { pet->requested = SNEEZE; }
void fc_hearts(FCPet *pet) { pet->requested = HEART; }

struct Clip {
    const char *group;
    unsigned char frames[12];
    int count;
    double duration;
};
static const struct Clip clips[] = {
    [IDLE] = {"idle", {0,1,2,3,4,5}, 6, 0},
    [FIRE] = {"flame", {4,5,6,7,6,5}, 6, 0},
    [CRY] = {"tears", {0,1,2,3,4,5,4,3,2,1}, 10, 0},
    [SLEEP] = {"sleep", {0,1,2,3,4,5}, 6, 12},
    [HEART] = {"hearts", {0,1,2,3,4,5,6,7,8,9,10}, 11, 2.2},
    [SNEEZE] = {"sneeze", {0,1,2,3,4,5,6,7}, 8, 1.6},
    [TONGUE] = {"rare", {0,2,2,2,0}, 5, 1},
    [SPARKLE] = {"rare", {0,3,3,3,0}, 5, 1},
    [EMBER] = {"rare", {0,4,5,5,4,0}, 6, 1.2},
    [WAVE] = {"wave", {0,1,2,1,2,1,2,1,0}, 9, 1.8},
    [HOP] = {"hop", {0,1,2,3,4,0}, 6, 1.2},
    [LOOK] = {"look", {0,1,1,1,0,2,2,2,0}, 9, 1.8},
    [DASH] = {"right", {0,1,2,3,4,5,6,7}, 8, 2.4}
};
static void start(FCPet *pet, enum Pose pose, double now) {
    pet->manual_dash = false;
    pet->pose = pose;
    pet->started = now;
}

FCFrame fc_step(FCPet *pet, double now, bool building, bool failed, bool right_corner, bool reduced) {
    // Both callers supply system uptime. Delayed UI callbacks still represent real elapsed idle time.
    double delta = pet->last_step >= 0 ? fmax(0, now - pet->last_step) : 0;
    pet->last_step = now;
    bool requested_dash = pet->requested == DASH && !reduced;
    bool playing_dash = pet->manual_dash && pet->requested == IDLE && !reduced &&
                        now - pet->started < clips[DASH].duration;
    if (failed || (building && !requested_dash && !playing_dash)) {
        enum Pose next = failed ? CRY : FIRE;
        if (pet->pose != next) start(pet, next, now);
        pet->requested = IDLE;
    } else if (pet->requested != IDLE) {
        enum Pose requested = pet->requested;
        pet->requested = IDLE;
        if (requested == DASH && reduced) requested = IDLE;
        if (requested == DASH) pet->until_dash = delay(DASH_MIN_SECONDS, DASH_MAX_SECONDS);
        start(pet, requested, now);
        pet->manual_dash = requested == DASH;
        pet->until_rare = delay(55, 115);
    } else if (pet->pose == FIRE || pet->pose == CRY) {
        start(pet, IDLE, now);
        pet->until_rare = delay(55, 115);
    } else if (pet->pose == IDLE) {
        pet->until_rare -= delta;
        if (!reduced) pet->until_dash -= delta;
        if (!reduced && pet->until_dash <= 0) {
            start(pet, DASH, now);
            pet->until_dash = delay(DASH_MIN_SECONDS, DASH_MAX_SECONDS);
        } else if (pet->until_rare <= 0) {
            static const enum Pose gestures[] = {HEART,TONGUE,SPARKLE,EMBER,WAVE,HOP,LOOK,SNEEZE};
            // Keep the original two-in-nine chance of a nap as the gesture set grows.
            enum Pose next = rand() % 9 < 2 ? SLEEP : gestures[rand() % (sizeof(gestures) / sizeof(gestures[0]))];
            start(pet, next, now);
            pet->until_rare = delay(55, 115);
        }
    } else if (now - pet->started >= clips[pet->pose].duration || (reduced && pet->pose == DASH)) {
        start(pet, IDLE, now);
    }

    const struct Clip *clip = &clips[pet->pose];
    double elapsed = fmax(0, now - pet->started);
    int index = reduced ? (clip->count > 2 ? 2 : 0) : (int)fmod(floor(elapsed * 5), clip->count);
    if (reduced && (pet->pose == HEART || pet->pose == SNEEZE)) index = clip->count / 2;
    FCFrame frame = {clip->group, clip->frames[index], 0, 0};
    if (pet->pose == DASH) {
        double progress = fmin(1, elapsed / clip->duration);
        bool running_left = (progress < 0.5) == right_corner;
        frame.group = running_left ? "left" : "right";
        frame.frame = (int)floor(elapsed * 10) % 8;
        frame.dx = (right_corner ? -44 : 44) * (1 - fabs(2 * progress - 1));
    } else if (pet->pose == HOP && !reduced) {
        frame.dy = 12 * sin(3.14159265 * fmin(1, elapsed / clip->duration));
    }
    return frame;
}
