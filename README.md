# Salem

Salem is the Sal Execution Model. It is a Zig implementation of the Sal programming language.

Sal is a purely functional, dynamically typed, simply-aritied, concatenative programming language.

## Data model

* Basic data types:
  * [RRB-Trees](https://hypirion.com/thesis.pdf) for arrays and byte arrays
  * B-Trees, for dictionaries, sets and multisets
  * Pairs and Variables
  * Primitive and constructed functions
  * A very minimal object system (needed for efficient mutual recursion)
  * Promises for lazy evaluation

* Numeric tower:
  * Fixnums
  * Arbitrary precision integers
  * Ratios
  * Complex numbers and quaternions (restricted to rational coefficients)
  * [Multisets (we will treat numbers as a proper subtype of multisets)](https://www.youtube.com/playlist?list=PLIljB45xT85D94vHAB8joyFTH4dmVJ_Fw)
  * We are explicitly not supporting IEEE 754 Floats, but we may at some point support [Posits](https://posithub.org/)

## Inspirations

* [Clojure](https://clojure.org/)
* [John Shutt's Kernel](https://web.cs.wpi.edu/~jshutt/kernel.html)
* [Racket](https://racket-lang.org/)
* [colorForth](https://colorforth.github.io/cf.htm)
* [RetroForth](https://retroforth.org/)
* [Joy](https://www.kevinalbrecht.com/code/joy-mirror/joy.html)
* [Factor](https://factorcode.org/)
* [Lua](https://www.lua.org/)
* [Erlang](http://www.erlang.org/)
* [Haskell](https://www.haskell.org/)
* [Zig](https://ziglang.org/)
* [Roc](https://www.roc-lang.org/)
