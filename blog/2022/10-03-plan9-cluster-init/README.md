# plan9 cluster init

This post contains more written out notes regarding the [projects/plan9](/projects/plan9) project.

## Table of contents

:::toc

## Introduction

So I've been playing around with plan9 and I't been really fun, but running it in qemu ist just weird. I've had the chance to pick up some second hand raspberry pi's on ebay-kleinanzeigen which include the following:

- 3x Raspberry Pi 1 A
- 3x Raspberry Pi 1 B+ v1.2
- 1x Raspberry Pi 2 B  v1.1

and I've still got a Pi 4 1GB here. So overall: 8 pi's which will be wonderful for building up a plan9 grid.

## What?

Imaging a network of computers in which you can use other computers resources more transparently. I'll write another blogpost as soon as I've read enough into it to be able to formulate it in a nice way. For now: It's an interesting form of distributed computing.

## Why?

Because I'm interested and might want to setup small "terminals" in the local hackspace consisting of a pi with a display, a mouse and a keyboard. This might allow people to get a glimpse into a world they might otherwise not and at the same time allow be to build up a system which allows playing around with such a grid which I've been planning since quite some time now.

## Why not just emulate them?

Well, it's quite a bit more fun to actually have a slightly physicaly distributed grid with a physical keyboard and mouse in front of all the edge nodes imho.

## And now?

Well, I'm currently reading into how to build a system so that they can all boot from a PXE server and don't require a local filsystem but instead use a fileserver. I've been thinking about building some kind of distributed fileserver, but more on that in another post.

