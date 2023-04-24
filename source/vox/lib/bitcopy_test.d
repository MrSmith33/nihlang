/// Copyright: Copyright (c) 2023 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko
module vox.lib.bitcopy_test;

import vox.lib;

@nogc nothrow:

void test_copyBitRange() {
	u64 permutations = 0;
	foreach(usize src; 0..64)
	foreach(usize dst; 0..64)
	foreach(usize length; 0..65 - max(src, dst))
	foreach(usize setBit; 0..64) {
		u64 input = 0;
		setBitAt(&input, setBit);
		u64 result = input;
		copyBitRange!u8(cast(u8*)&result, dst, src, length);

		if (!isResultValid(input, result, dst, src, length)) {
			printTestCase(input, dst, src, length);
			onTestFail(input, result, dst, src, length);
		}
		++permutations;
	}
	writefln("%s permutations", permutations);
}

void testCase(
	string input,
	usize dst,
	usize src,
	usize length,
	string file = __FILE__,
	int line = __LINE__)
{
	u64 inputBits;
	usize index = 0;
	foreach(char bit; input) {
		if (bit == '1') setBitAt(&inputBits, index);
		if (bit == '0' || bit == '1') ++index;
	}
	testCase(inputBits, dst, src, length, file, line);
}

void testCase(
	const u64 input,
	usize dst,
	usize src,
	usize length,
	string file = __FILE__,
	int line = __LINE__)
{
	u64 result = input;

	copyBitRange!u8(cast(u8*)&result, dst, src, length);

	if (isResultValid(input, result, dst, src, length)) {
		onTestSuccess(input, result, dst, src, length);
	} else {
		onTestFail(input, result, dst, src, length, file, line);
	}
}

bool isResultValid(
	const u64 input,
	const u64 result,
	usize dst,
	usize src,
	usize length) {
	foreach(index; 0..64) {
		usize srcIndex;
		if (index >= dst && index < dst + length) {
			srcIndex = index - dst + src;
		} else {
			srcIndex = index;
		}
		bool expectedBit = getBitAt(cast(usize*)&input, srcIndex);
		bool resultBit = getBitAt(cast(usize*)&result, index);
		if (expectedBit != resultBit) return false;
	}
	return true;
}

void onTestSuccess(
	const u64 input,
	const u64 result,
	usize dst,
	usize src,
	usize length)
{
	printMarker(10, src, length, 'v');
	write("Input:    ");
	printBitsln(&input, 0, 64);

	printMarker(10, dst, length, 'v');
	write("Result:   ");
	printBitsln(&result, 0, 64);
}

noreturn onTestFail(
	const u64 input,
	u64 result,
	usize dst,
	usize src,
	usize length,
	string file = __FILE__,
	int line = __LINE__)
{
	printMarker(10, src, length, 'v');

	write("Input:    ");
	printBitsln(&input, 0, 64);

	printMarker(10, dst, length, 'v');

	write("Result:   ");
	printBitsln(&result, 0, 64);

	write("Expected: ");
	foreach(index; 0..64) {
		usize srcIndex;
		if (index >= dst && index < dst + length) {
			srcIndex = index - dst + src;
		} else {
			srcIndex = index;
		}
		bool expectedBit = getBitAt(cast(usize*)&input, srcIndex);
		write(cast(char)('0' + expectedBit));
		if (index+1 < 64 && (index+1)%8 == 0) write(' ');
	}
	writeln;

	write("          ");
	foreach(index; 0..64) {
		usize srcIndex;
		if (index >= dst && index < dst + length) {
			srcIndex = index - dst + src;
		} else {
			srcIndex = index;
		}
		bool expectedBit = getBitAt(cast(usize*)&input, srcIndex);
		bool resultBit = getBitAt(cast(usize*)&result, index);
		if (expectedBit != resultBit) write('^');
		else write(' ');
		if (index+1 < 64 && (index+1)%8 == 0) write(' ');
	}
	writeln;

	panic(line, file, 3, "Test error\n");
}

void printTestCase(
	const u64 input,
	usize dst,
	usize src,
	usize length)
{
	write("//");
	printMarker(8, src, length, 'v');
	write("testCase(\"");
	printBits(&input, 0, 64);
	writefln("\", %s, %s, %s);", dst, src, length);
	write("//");
	printMarker(8, dst, length, '^');
}
