// Whole numbers that two threads can share safely without a lock.
//
// The sample ring (Sources/ParticleAccelerator/Audio/SampleRing.swift) hands sound from
// the audio thread to the analyser. The audio thread mustn't take a lock or wait
// (CLAUDE.md rule 6), so the two sides agree through one shared count instead. Swift's
// own `Atomic` needs macOS 15 and this project supports macOS 14, so these few lines of
// C do the job with the C standard library's atomics.
#ifndef ATOMIC_INTEGERS_H
#define ATOMIC_INTEGERS_H

#include <stdatomic.h>
#include <stdint.h>

/// Reads the number, and everything the other thread wrote before storing it.
static inline int64_t pa_atomic_load_acquire(const int64_t *value) {
    return atomic_load_explicit((const _Atomic int64_t *)value, memory_order_acquire);
}

/// Stores the number after everything this thread wrote before it.
static inline void pa_atomic_store_release(int64_t *value, int64_t newValue) {
    atomic_store_explicit((_Atomic int64_t *)value, newValue, memory_order_release);
}

#endif
