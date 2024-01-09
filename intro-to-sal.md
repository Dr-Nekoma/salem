# Sal

## Introduction

Sal is a purely functional, dynamically typed, simply-aritied, concatenative
programming language. It puts a heavy emphasis on uniformity and smoothness,
discarding any feature that would introduce second-class entities into the
language and taking a different approach to metaprogramming that retains the
pre-processing nature of macros without their accompanying downsides.

Its control flow is based on failure rather than switching on booleans, making
it similar to logic languages such as Prolog or Mercury, though it lacks their
non-determinism features.

The core ideas of Sal and the way the fit together are more important than
the particular details of a any given implementation. In that sense, Sal is
intended to be akin to Lisp and Forth in that there could many different
dialects as opposed to there being a single canonical implementation.

Let's briefly cover the high-level concepts behind Sal before going into
details on the language's data model, theoretical foundation and syntax.

The language is still in development, so everything in this file may change.

### Purely functional

Purely functional normally means there are no side-effects in the language.
In particular, there's no mutation at the language level (though there may
be mutations for efficiency reasons at the implementation level).

In the context of Sal, however, since its type system is dynamic there's no
getting away from the fact that operations may fail. So in Sal, it is actually
the case that there's only one possible side-effect: failure.

I don't consider this to detract from its purity, since logic languages also
feature failure and are still considered pure. In any case the most important
characteristic of functional programming is preserved: that given the same
inputs, a given function will always return the same outputs (or fail, as the
case may be).

While there could in principle be Sal dialects that are not purely functional,
making that fit with the other core features is tricky and not to be taken
lightly.

### Dynamically typed

In Sal, values have types which are checked at runtime as needed.

This is different from statically typed languages where expressions (not
values) have types which are checked at compile time before the program ever
runs.

Dynamic typing is simpler to implement, and more flexible in its usage, though
admittedly can let certain errors happen at runtime that static types would
prevent at compile time.

Given Sal's take on metaprogramming and on making functions more inspectable,
there could be Sal dialects that perform some level of static typechecking
entirely in userspace, similar to how Typed Racket came about.

### Simply-aritied

Functions in Sal are simply-aritied: that is, they take a known, fixed number
of arguments and return another known, fixed number of inputs. Function arity
is inspectable.

Although some functions may support arity overloading, that is being treated
as if they have different arities in different contexts, there are no variadic
functions in Sal. In particular, unlike other concatenative languages like
Factor and Kitten, there is no such thing as row-polymorphic arity in Sal.

This is a core feature without which Sal wouldn't be Sal. While on its own
this would be very limiting, the presence of metaprogramming mitigates
most of its downsides.

### Concatenative

Sal functions are written as a composition of pre-existing functions, with
the syntax for composition being juxtaposition. This is in contrast to more
mainstream languages where syntactic juxtaposition denotes application, i.e.
function calling.

As a result, the feel of writing Sal code should be reminiscent of writing
shell pipelines in Unix, except Sal has a richer data model than simple text
streams.

Unlike most concatenative languages, Sal is not actually stack-based. Although
it could be implemented as such, and syntactically you could reason about it
as if it were stack-based, the core semantics is entirely about function
composition. This is reinforced by the fact that Sal is simply-aritied: each
function has a known number of inputs and outputs and no way of seeing if
there are more inputs available than it actually takes. In that way, the
emphasis is squarely on the flow of data between functions with no appeal to
actual implementation details.

While there could be dialects of Sal which are not concatenative, taking that
as the starting point would complicate the metaprogramming model. It would
reintroduce all the hygiene issues that macros struggle with and that Sal
tries to escape from. The concatenative model is chosen because it sidesteps
any question of variable scope by not having variables in the first place.

### Metaprogramming

Sal's approach to metaprogramming is heavily inspired by the Forth and Lisp
families. It also bears similarities to Zig's comptime, though that's a result
of convergent design evolution rather than being an influence.

To explain how it works, it helps to explain its influences. Forth's model is
the more primitive one, so we'll start from that.

#### Forth

In languages of the Forth family, there is an outer interpreter that reads in
the source code as text and compiles it to a form that is understood by the
inner interpreter, which is essentially a virtual machine (though it could be,
and in some cases is, actual hardware). The outer interpreter is implemented
in, and heavily tied with, the inner interpreter.

By default, the outer interpreter treats the source code as a sequence of
words delimited by whitespace. It has two modes: execution and compilation.
It starts in execution mode, but alternates frequently between the two in
the course of reading.

Interpretation of a word is as follows:
1. If the word looks like a number, treat it as a constant. In execution mode,
the number is pushed on the stack. In compilation mode, an instruction to push
the number on the stack is compiled into the word currently being compiled.
2. Look at the current vocabulary for a definition of the word. If the word is
marked as immediate, or if we are in execution mode, execute it immediately. If
the word is not immediate and we are in compilation mode, compile a call to it
into the word currently being compiled.

The key here is that immediate words will be executed even when compiling,
and they can do arbitrary processing: they may consume input that otherwise
would be parsed by the outer interpreter when the word finishes executing,
and they may compute and emit code in arbitrary ways. This is very powerful,
allowing the embedding of arbitrary syntax extensions even if they don't look
like Forth code. But there are two downsides: any syntax extension needs to
deal with the complexities of parsing a character stream as opposed to
structured data, and the syntax extensions may look nothing like normal Forth.

#### Lisp

In languages of the Lisp family, there is a reader that parses textual source
code into Lisp data. The data then goes to the particular Lisp's eval function
which executes it. At this point there are two distinct strategies that Lisps
may employ for metaprogramming: macros, which are by far the more common, and
fexprs which are semantically cleaner but have been discarded for historical
reasons.

The main difference between them is that fexprs are first-class and operate at
run-time, while macros are second-class and introduce a separate expansion
phase before actual execution of the program. Both fexprs and macros operate on
structured Lisp data, which means that they look and feel like ordinary Lisp
code but also that they cannot introduce extensions at the lexical level like
Forth immediate words can.

Additionally, many Lisps including Racket and Common Lisp also allow so-called
read macros which, like Forth immediate words, also operate at the level
character streams with similar pros and cons. However, their usage is uncommon
due to a cultural preference among Lispers for regular macros since they look
like ordinary Lisp code.

#### Sal

From Forth, Sal takes the idea of doing metaprogramming in the reader using
ordinary functions. It ditches the immediate/non-immediate distinction as well
as the power and responsibility of operating on the level of text.

Like Lisp macros and fexprs, Sal's notion of metaprogramming operates on
structured data rather than text. Like read macros, it happens during the read
phase. The reasoning behind it is that there's no need to artificially
introduce a phase distinction between macro and non-macro code when there's
already a natural phase distinction between reading and evaluating that we
can piggyback on.

The basic idea is this: the Sal reader has two modes, code and data, and it
starts in code mode. It can switch between the modes with via explicit
annotations similar to Lisp's quasiquotation mechanism. When it reads a value,
if that value is a var or a combo and the reader is in code mode, it will
immediately interpret the value before continuing with the reading:

- Vars are treated as variable references to data available in the reader's
environment. Typically they are used to refer to user-defined values, but they
can also refer to modules, files that the user wants to embed in the program,
environment variables, and other such things.
- Combos are treated as function calls, with the left element being the the
function and its right element being the argument or argument list.

The interpretation result then takes the place of the original value that was
read as if it had appeared literally in the source code in data mode.

This way of doing things has a few implications:
- There is no distinction between functions and macros. Indeed, syntax
extensions are simply ordinary functions that happen to be called at read-time.
- There are no second-class entities introduced into the language.
- Because Sal is concatenative, we often want to introduce new syntax for the
sake of building functions more conveniently. Those functions will then be
composed into the body of other functions in the usual manner of concatenative
languages.
- The above points taken together mean that in Sal, *metaprogramming and
ordinary higher-order programming are actually the same thing*.

## Data Model

In Sal, every value is a function. Functions carry around their arity information.
Each function has a main arity, which is what is returned by default when we look
up a function's arity, though it may also support others. Unless otherwise specified,
whenever a function's arity is mentioned we are referring to the main arity.

An arity is simply a pair of natural numbers, describing how many inputs are
required and how many outputs are produced from those required inputs. It is
possible to give a function more arguments than it requires, in which case
those values simply flow through unchanged. We shall elaborate on the
implications of this model in the next section; for now, this exposition is
sufficient to explain Sal's basic data types.

### Tuples

Functions with an input arity of 0 are called tuples. A tuple's size is
considered to be its output arity. Tuples are by far the most common data type
in Sal, because they represent constant values.

Tuples may be eager or lazy. When referring to tuples in text, by default we
assume them to be eager unless otherwise specified. The main difference between
them is whether or not we know statically if they will fail.

Tuples of size 0 are the most primitive values in Sal. Because calling a function
may fail, and tuples have no inputs, a failing tuple will always fail while a
successful tuple will always succeed. This means that tuples of size 0 are the
closest thing to boolean values that Sal has. In particular, the successful
0-tuple can be identified with the boolean value `true`, but it is also the
canonical empty tuple and the canonical 0-input identity function. Meanwhile,
the failing 0-tuple is identified with the boolean value `false`, though it
is also the canonical 0-in 0-out failure function. Lazy 0-tuples are simply
booleans whose value cannot be determined without running them, and may
either succeed or fail.

Tuples of size 1 can be divided into two groups: promises and literals. Promises
are the primary mechanism for lazy evaluation, though they are also important
for composing higher order functions. Meanwhile, literals correspond to what
other languages would consider their value types. The distinguishing feature of
literals is that _they are statically known return themselves when called_.

_TODO_

## Theory of Simply-aritied Languages

_TODO_

## Syntax

_TODO_
