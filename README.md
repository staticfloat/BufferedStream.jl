# BufferedStream

This module provides a basic datatype used to buffer incoming stream data in an a format friendly to processing.  The basic API is to create a `LinkedBufferStream` (hinting at the fact that it is implemented using a linked list) and then create `views` on that stream:

```julia
using BufferedStream

stream = LinkedStream{Float64}()
view = StreamView(stream)
```

After creating a `LinkedStream`, samples can be pushed to it via `push!`, and these samples will appear in the `view`:

```julia
push!(stream, Float64[1,2,3,4,5])
view[1] + view[2] == 3
```

`StreamView` objects provide an `Array`-like interface, seamlessly bridging over the multiple chunks of data `push!`'ed onto the `stream`.  The really interesting behavior comes via `shift_origin!()`, which allows a `view` to shift forward in time, leaving samples behind.  This allows an algorithm to process a stream of data, buffering data seamlessly until it is determined that some old samples are no longer needed.  At that point in time, the `view` can be shifted forward, and old chunks will be automatically garbage collected:

```julia
push!(stream, Float64[6,7,8,9,10])
shift_origin!(view, 6)
# Original chunk added above is now free to be garbage collected
view[1:4] == Float64[7,8,9,10]
```

New views can be created easily from old views:
```julia
view2 = StreamView(view)
view[1] == view2[1]
```

As well as from streams, however note that they will point to the end of the last chunk added to the `StreamView`; you must `push!()` more samples onto the stream.
```julia
view2 = StreamView(stream)
view2[1] # This throws a BoundsError
push!(stream, Float64[1,2,3])
view2[1:3] == Float64[1,2,3]
```

# Important Notes

* `LinkedStream`'s do not copy the data pushed onto them; they simply store a reference:
```julia
stream = LinkedStream{Float64}()
view = StreamView(stream)
data = Float64[1,2,3]
push!(stream, data)

view[1] == 1
data[1] = 2
view[1] == 2
```

* Samples in the past relative to all views are unreachable and garbage collectable immediately.  Do not advance views beyond samples you wish to process in the future.

* `view` objects do not define a `setindex!()` method; assignments do not work, partially due to the fact that the chunks underlying the views would be mutated, and partially because the spirit of this package is to provide a read-only view of the incoming stream; processing that requires modifications of the data should create a copy of the data and operate upon that.

[![Build Status](https://travis-ci.org/staticfloat/BufferedStream.jl.svg?branch=master)](https://travis-ci.org/staticfloat/BufferedStream.jl)
