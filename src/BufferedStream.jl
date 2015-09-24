module BufferedStream

import Base: getindex, length, push!, eltype, linearindexing, size, similar, finalizer
export BufferedStreamView, IndexedBufferedStream
export shift_origin!, view!

# BufferedStream is an abstraction of a data stream that flows, but remembers
# as much of the stream as views/iterators upon it force it to.
abstract AbstractBufferedStream{T}

# A view that keeps track of where it is in a BufferedStream
type BufferedStreamView{T} <: DenseArray{T, 1}
    stream::AbstractBufferedStream{T}

    # Where is our origin?
    chunk_idx::Int64
    sample_offset::Int64

    # What is our origin's absolute index?
    abs_idx::Int64
end

# Define stuff for AbstractArray
linearindexing(::BufferedStreamView) = Base.LinearFast()
# Calculates how many samples after our origin there are buffered up
length(view::BufferedStreamView) = max(sum(Int64[length(z) for z in view.stream.data_chunks[view.chunk_idx:end]]) - view.sample_offset, 0)
size(view::BufferedStreamView) = (length(view),)
similar(view::BufferedStreamView, T, dims::Tuple{Int64}) = T[z for z in view]
eltype{T}(view::BufferedStreamView{T}) = T

# Construct a new view off of a stream
function BufferedStreamView{T}(stream::AbstractBufferedStream{T}, offset::Integer = 0)
    view = BufferedStreamView{T}(stream, 1, 0, stream.samples_discarded)
    shift_origin!(view, offset)
    push!(stream.views, WeakRef(view))
    return view
end

# Construct a new view off of another view
function BufferedStreamView{T}(v::BufferedStreamView{T})
    view = BufferedStreamView{T}(v.stream, v.chunk_idx, v.sample_offset, v.stream.samples_discarded)
    push!(v.stream.views, WeakRef(view))

    # When a view dies, take its weakref with it
    finalizer(view, (view) -> begin
        idx = 1
        while idx <= length(view.stream.views)
            if view.stream.views[idx] == view
                splice!(view.stream.views, idx)
            else
                idx += 1
            end
        end
    end)
    return view
end

# Move this view forward `offset` samples
function shift_origin!(view::BufferedStreamView, offset::Integer)
    # Bump up the absolute index immediately
    view.abs_idx += offset

    # Figure out how many chunks we need to move forward
    for chunk in view.stream.data_chunks
        if offset >= length(chunk) - view.sample_offset
            # This means we skip this chunk entirely
            offset -= length(chunk) - view.sample_offset
            view.chunk_idx += 1
            view.sample_offset = 0
        else
            # This means we land somewhere within this chunk
            view.sample_offset += offset
            clean!(view.stream)
            return
        end
    end

    # We have passed the end of the data we've received; chunk_idx  is set to
    # the index of the next chunk that will be created, so set sample_offset to the
    # remaining offset that we haven't gobbled up with the
    view.sample_offset = offset
    clean!(view.stream)
    return
end


# If someone asks for an index, serve it if we can!
function getindex(view::BufferedStreamView, idx::Integer)
    # Calculate which chunk to read from:
    curr_idx = idx + view.sample_offset
    for chunk in view.stream.data_chunks[view.chunk_idx:end]
        # Is the current offset contained within this chunk?  If so, return it!  Otherwise, continue
        if curr_idx <= length(chunk)
            return chunk[curr_idx]
        else
            curr_idx -= length(chunk)
        end
    end
    throw(BoundsError())
end

# Don't define setindex!() for now; that may or may not be a great idea.





type IndexedBufferedStream{T} <: AbstractBufferedStream{T}
    # Keep track of the views out in the world
    views::Array{WeakRef}

    # This is where our lovely loving data gets stored
    data_chunks::Array{Array{T}}

    # How many chunks have we discarded?
    chunks_discarded::Int64

    # How many samples have we discarded?
    samples_discarded::Int64

    IndexedBufferedStream() = new(BufferedStreamView[], Array[], 0, 0)
end

# The length is how much stuff is buffered up right now, total
length(stream::IndexedBufferedStream) = sum([length(z) for z in stream.data_chunks])

# Pushes a new chunk onto the end of the stream.  Note that if there are no viewers for this stream
# registered, we just throw the bits away immediately.
function push!{T}(stream::IndexedBufferedStream{T}, chunk::Array{T})
    if isempty(stream.views)
        stream.chunks_discarded += 1
        stream.samples_discarded += length(chunk)
    else
        push!(stream.data_chunks, chunk)
    end
    return
end

# Remove any chunks that aren't being pointed to by views anymore
function clean!(stream::IndexedBufferedStream)
    # Find the first chunk in use by any of the views
    min_chunk = length(stream.data_chunks)
    for view in stream.views
        min_chunk = min(view.value.chunk_idx, min_chunk)
    end

    # If min_chunk is > 1, we have work to do; chunks to free!
    if min_chunk > 1
        # Free the chunks in one swell foop
        stream.data_chunks = stream.data_chunks[min_chunk:end]
        stream.chunks_discarded += min_chunk - 1

        # Update the views so they are still pointing to the proper chunks
        for view in stream.views
            view.value.chunk_idx -= min_chunk - 1
        end
    end
    return
end

end # module
