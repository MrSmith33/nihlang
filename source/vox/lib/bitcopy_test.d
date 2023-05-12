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
		// different ptr
		foreach(usize dstBit; 0..64) {
			u64 dstInput = 0;
			setBitAt(&dstInput, dstBit);

			u64 resultSrc = input;
			u64 resultDst = dstInput;
			copyBitRange!u8(cast(u8*)&resultDst, cast(u8*)&resultSrc, dst, src, length);

			foreach(index; 0..64) {
				bool expectedBit;
				if (index >= dst && index < dst + length) {
					expectedBit = getBitAt(cast(usize*)&input, index - dst + src);
				} else {
					expectedBit = getBitAt(cast(usize*)&dstInput, index);
				}
				bool resultBit = getBitAt(cast(usize*)&resultDst, index);
				if (expectedBit != resultBit) assert(false);
			}
			assert(resultSrc == input);
			++permutations;
		}
		// same ptr
		{
			u64 result = input;
			copyBitRange!u8(cast(u8*)&result, cast(u8*)&result, dst, src, length);

			if (!isResultValid(input, result, dst, src, length)) {
				printTestCase(input, dst, src, length);
				onTestFail(input, result, dst, src, length);
			}
			++permutations;
		}
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

	copyBitRange!u8(cast(u8*)&result, cast(u8*)&result, dst, src, length);

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

void testCase2(
	string dstMem,
	string srcMem,
	usize dst,
	usize src,
	usize length,
	string file = __FILE__,
	int line = __LINE__)
{
	u64 dstBits;
	u64 srcBits;
	usize index = 0;
	foreach(char bit; dstMem) {
		if (bit == '1') setBitAt(&dstBits, index);
		if (bit == '0' || bit == '1') ++index;
	}
	index = 0;
	foreach(char bit; srcMem) {
		if (bit == '1') setBitAt(&srcBits, index);
		if (bit == '0' || bit == '1') ++index;
	}
	testCase2(dstBits, srcBits, dst, src, length, file, line);
}

void testCase2(
	const u64 dstBits,
	const u64 srcBits,
	usize dst,
	usize src,
	usize length,
	string file = __FILE__,
	int line = __LINE__)
{
	u64 dstMem = dstBits;
	u64 srcMem = srcBits;

	copyBitRange!u8(cast(u8*)&dstMem, cast(u8*)&srcMem, dst, src, length);

	if (isResultValid2(dstBits, srcBits, dstMem, dst, src, length)) {
		onTestSuccess(srcBits, dstMem, dst, src, length);
	} else {
		onTestFail(srcBits, dstMem, dst, src, length, file, line);
	}
}

bool isResultValid2(
	const u64 dstBits,
	const u64 srcBits,
	const u64 result,
	usize dst,
	usize src,
	usize length) {
	foreach(index; 0..64) {
		bool expectedBit;
		if (index >= dst && index < dst + length) {
			expectedBit = getBitAt(cast(usize*)&srcBits, index - dst + src);
		} else {
			expectedBit = getBitAt(cast(usize*)&dstBits, index);
		}
		bool resultBit = getBitAt(cast(usize*)&result, index);
		if (expectedBit != resultBit) return false;
	}
	return true;
}
