using BufferedStream
using Base.Test

# Construct a stream and a view of said stream
stream = LinkedStream{Float64}()
view = StreamView(stream)

# Initially, any kind of access on view is going to throw
@test_throws BoundsError view[-1]
@test_throws BoundsError view[0]
@test_throws BoundsError view[1]
@test view.chunk == stream.latest
@test isnull(view.chunk.next)

# Add a chunk of data
data = Float64[3.1,4.1,5.9,2.6,5.3]
push!(stream, data)
@test view.chunk != stream.latest
@test view.chunk.next.value == stream.latest
@test isnull(stream.latest.next)

# Print out a StreamChunk and a StreamView to see what it looks like:
display(stream)
println()
display(view)
println()

# Ensure that the data came through okay, and that out of bounds accesses are recognized as such
@test length(view) == length(data)
for idx in 1:length(data)
    @test view[idx] == data[idx]
end
@test_throws BoundsError view[-1]
@test_throws BoundsError view[0]
@test_throws BoundsError view[6]

# Verify that the LinkedStream does not copy data:
data[1] = 3.2
@test view[1] == 3.2
data[1] = 3.1
@test view[1] == 3.1

# Add a second chunk, ensure that it is seamlessly integrated into our view
push!(stream, data)
for idx in 1:length(data)
    @test view[idx] == data[idx]
    @test view[idx + length(data)] == data[idx]
end

# Move view forward a few samples, ensure the shift worked:
shift_origin!(view, 2)
@test length(view) == 2*length(data) - 2
for idx in 1:length(view)
    @test view[idx] == data[mod1(idx + 2, length(data))]
end

# Test that the underlying data is still the original representations
@test view.chunk.data == data

# Move view forward enough to get into the next chunk
shift_origin!(view, 4)
@test length(view) == length(data) - 1
for idx in 1:length(view)
    @test view[idx] == data[idx + 1]
end

# Now add a bunch of chunks
push!(stream, Float64[1:100 ...])
push!(stream, Float64[1:100 ...])
push!(stream, Float64[1:100 ...])
push!(stream, Float64[1:100 ...])

# Ensure our length can still be found, despite all appearances to the contrary
@test length(view) == 404

# Shift the view, and start playing with more complex operations/indexing
shift_origin!(view, 157)
@test view[48:147] == Float64[1:100 ...]
@test length(view[48:end]) == 200
@test mean(view[48:end]) == mean(1:100)
@test sum(view[48:57]) == sum(1:10)

# Create a second view off of this view, and a third view off of the stream
view2 = StreamView(view)
view3 = StreamView(stream)

# Test to make sure that the linked list looks like we'd expect
@test view3.sample_offset == 0
@test view2.sample_offset == view.sample_offset
@test view2.chunk == view.chunk
@test view2.chunk.next.value.next.value == view3.chunk
@test isnull(view3.chunk.next)

# Test to make sure the values look like we'd expect
@test view2.abs_idx == view.abs_idx
@test view3.abs_idx == view.abs_idx + 48 + 99
@test view2[1] == view[1]
@test view3[1] == view[148]
