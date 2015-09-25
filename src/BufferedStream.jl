__precompile__()
module BufferedStream

import Base: getindex, length, push!, eltype, linearindexing, size, similar, show
export LinkedStream, StreamView
export shift_origin!

# The foundation of a linked-list of chunks
type StreamChunk{T}
    data::Array{T,1}
    next::Nullable{StreamChunk{T}}

    StreamChunk() = new(T[], Nullable{StreamChunk{T}}())
    StreamChunk(data::Array{T,1}) = new(data, Nullable{StreamChunk{T}}())
end

# Just return the length of this chunk.
length(chunk::StreamChunk) = length(chunk.data)

# Show something well-behaved
function show(io::IO, chunk::StreamChunk)
    write(io, "StreamChunk")
    Base.showlimited(io, chunk.data)
    if isnull(chunk.next)
        write(io, " -> <null>")
    else
        write(io, " -> StreamChunk")
    end
end

# The object that keeps track of the last chunk in the linked list
type LinkedStream{T}
    # This is where our lovely loving data gets stored
    latest::StreamChunk{T}

    # How many samples have we discarded?
    samples_past::Int64

    # We can only create one that initializes with an empty list
    LinkedStream() = new(StreamChunk{T}(), 0)
end

# Pushes a new chunk onto the end of the stream.  Julia should automatically garbage collect
# the chunks any views have moved past, since they will no longer be accessible.
function push!{T}(stream::LinkedStream{T}, data::Array{T,1})
    # Create a new chunk based off of this data
    chunk = StreamChunk{T}(data)

    # Account for the samples we're putting behind us
    stream.samples_past += length(stream.latest)

    # Move the new chunk into the lead position
    stream.latest.next = Nullable(chunk)
    stream.latest = chunk
    return
end

function show{T}(io::IO, stream::LinkedStream{T})
    write(io, "LinkedStream{$(string(T))}, $(stream.samples_past) samples post-origin")
end




# A view that acts like an array, but that you can move forward in the stream
type StreamView{T} <: DenseArray{T, 1}
    # Where is our origin?
    chunk::StreamChunk{T}
    sample_offset::Int64

    # What is our origin's absolute index?
    abs_idx::Int64
end

# Define stuff for AbstractArray
linearindexing(::StreamView) = Base.LinearFast()
# Calculates how many samples after our origin there are buffered up
function length(view::StreamView)
    # Count total length of all chunks after the origin of this guy
    len = length(view.chunk)
    chunk = view.chunk
    while !isnull(chunk.next)
        chunk = chunk.next.value
        len += length(chunk)
    end

    # Subtract sample_offset, and ensure that zero is the smallest we will ever return
    return max(len - view.sample_offset, 0)
end

size(view::StreamView) = (length(view),)
eltype{T}(view::StreamView{T}) = T




# Construct a new view off of a stream, with an optional offset
function StreamView{T}(stream::LinkedStream{T})
    offset = length(stream.latest)
    return StreamView{T}(stream.latest, offset, stream.samples_past + offset)
end

# Construct a new view off of another view (easy peasey; just a straight copy)
StreamView{T}(v::StreamView{T}) = StreamView{T}(v.chunk, v.sample_offset, v.abs_idx)

# Move this view forward `offset` samples; we only support positive offsets!
function shift_origin!(view::StreamView, offset::Integer)
    if offset < 0
        throw(DomainError())
    end

    # Bump up the absolute index immediately
    view.abs_idx += offset

    # Move through chunks until offset lands within this current chunk, or we run out of chunks
    while (offset >= length(view.chunk) - view.sample_offset) && !isnull(view.chunk.next)
        offset -= length(view.chunk) - view.sample_offset
        # sample_offset can be greater than length(view.chunk), if we had shifted past the end of
        # buffered data previously; this will move us forward as far as we can
        view.sample_offset = max(view.sample_offset - length(view.chunk), 0)
        view.chunk = view.chunk.next.value
    end

    # Once our offset lands within this chunk, update the sample_offset and call it good!  If we are
    # past the end of the current offset (e.g. we are shifting into the great unknown) do the same,
    # simply leaving sample_offset greater than length(view.chunk)
    view.sample_offset += offset
    return
end

# If someone asks for an index, serve it if we can!
function getindex(view::StreamView, idx::Integer)
    # Scoot us forward as much as the sample_offset requires
    idx += view.sample_offset

    # Zoom through chunks as much as we need
    chunk = view.chunk
    while idx > length(chunk)
        # If we can't move forward anymore, throw a BoundsError!
        if isnull(chunk.next)
            throw(BoundsError())
        end
        idx -= length(chunk)
        chunk = chunk.next.value
    end

    # If we got to the correct chunk, index into it and yield the data!
    return chunk.data[idx]
end

# Don't define setindex!() for now; that may or may not be a great idea.

end # module
