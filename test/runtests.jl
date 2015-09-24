using BufferedStream
using Base.Test

# Test that things throw with negatives, test that things get thrown away, etc...
stream = IndexedBufferedStream{Float64}()

# First, test that samples pushed when there are no viewers are thrown away
@test length(stream) == 0
@test length(stream.views) == 0
push!(stream, [1.0,2.0,3.0])
@test length(stream) == 0

# Next, test that if we register a view, we can start buffering samples
view = BufferedStreamView(stream)
@test length(stream.views) == 1
push!(stream, [1.0,2.0,3.0])
@test length(stream) == 3
@test length(view) == 3
push!(stream, [4.0,5.0,6.0])
@test length(stream) == 6
@test length(view) == 6

# Test that indexing is on the up and up
for idx in 1:length(stream)
    @test view[idx] == Float64(idx)
end

# Ensure that we can throw out-of-bounds stuffage
@test_throws BoundsError view[0]
@test_throws BoundsError view[7]
@test_throws BoundsError view[-1]

# Test cloning a view
view2 = BufferedStreamView(view)
@test length(stream.views) == 2
for idx in 1:length(stream)
    @test view2[idx] == view[idx]
    @test view2[idx] == Float64(idx)
end

# Test moving one of the iterators
shift_origin!(view2, 4)
@test view2.chunk_idx == 2
@test view2.sample_offset == 1
@test length(view) == 6
@test length(view2) == 2
@test view[5] == view2[1]
@test view[6] == view2[2]
@test_throws BoundsError view2[3]

# Now move another iterator, this one moves the views such that the first chunk is freeable
shift_origin!(view, 3)
@test length(stream.data_chunks) == 1
@test length(stream) == 3
@test view[2] == view2[1]
@test view[3] == view2[2]

# Prove that the view's chunk indices have been updated after making the transition above
@test view.chunk_idx == 1
@test view2.chunk_idx == 1

# Let's make sure we can use things like sum(), mean(), etc...
@test sum(view) == 15
@test mean(view) == 5.0

# Let's test out having lots of weirdly shaped chunks and iterating over them
push!(stream, map(Float64, [1:7...]))
push!(stream, map(Float64, [1:57...]))
push!(stream, [1.0])
push!(stream, [1.0])
push!(stream, [1.0])
@test length(stream) == 70

@test view[1:10] == Float64[1,2,3,4,5,6,7,1,2,3]
