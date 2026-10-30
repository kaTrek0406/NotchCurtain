# Design

## Context

A developer uses a Mac with a camera notch while working across agent terminals. The panel should blend into the notch and reveal useful context on demand.

## Visual system

Use a restrained black surface, native SF typography, compact spacing, and subtle neutral separators. Reserve color for clear working, ready, and error states; pair each state color with readable text.

## Layout and motion

The collapsed panel follows detected notch geometry. On hover, it expands into a compact status row, tab strip, and scrolling workspace list. Use a damped spring and a short ease-out transition; respect reduced motion.
