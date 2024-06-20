/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Notes:
// DMD does not produce .lib and .exp files if program contains no symbols marked as `export`
// When previous build was done with different compiler, .pdb files can confuse linker making it exit with an error.
//
// macos
//   -platform_version <platform> <target_version> <sdk_version>
//   platform = macos
//   target_version = macos
//   sdk_version = macos
//
//   -L-ld_classic can be useful on macos
//
// if -defaultlib=phobos2-ldc-lto,druntime-ldc-lto fails with /usr/bin/ld: /tmp/lto-llvm-42ff39.o:(.data._D3etc1c4curl12__ModuleInfoZ+0x10): undefined reference to `_D3std6socket12__ModuleInfoZ'
// one needs to use another linker, such as gold, via -linker=gold flag
// https://github.com/ldc-developers/ldc/issues/4289
//
// Webassembly
//   https://github.com/bytecodealliance/wasmtime/issues/8697 wasi threads
//   https://wiki.dlang.org/Generating_WebAssembly_with_LDC
//   https://webassembly.org/roadmap/
//   ldc2 -mtriple=wasm32-wasi -mattr=help
//   (start $__wasm_init_memory) is produced by the compiler. `start` shouldn't be overridden
//   __wasm_init_memory performs thread-safe static memory init.
//   `start` function is called by every thread before running entry point
//
// source ~/dlang/ldc-1.32.0/activate
module builder;

import core.time : MonoTime, Duration;
import std.algorithm : filter, joiner, canFind, map, filter, move;
import std.range : empty, array, chain;
import std.file : thisExePath;
import std.path : dirName, buildPath, setExtension;
import std.conv : text;
import std.stdio;
import std.string : format, lineSplitter, strip;

int main(string[] args)
{
	string artifactDir = thisExePath.dirName.dirName.buildPath("bin").makeCanonicalPath;
	string srcDir = thisExePath.dirName.dirName.buildPath("source").makeCanonicalPath;

	Config[] configs = [
		Config("nih-cli",    "nihcli.d", artifactDir, srcDir, TargetType.executable, "nih"),
		Config("nih-static", "libnih.d", artifactDir, srcDir, TargetType.staticLibrary, "nih"),
		Config("nih-shared", "libnih.d", artifactDir, srcDir, TargetType.sharedLibrary, "nih"),
		Config("vbe-static", "libvbe.d", artifactDir, srcDir, TargetType.staticLibrary, "vbe"),
		Config("vbe-shared", "libvbe.d", artifactDir, srcDir, TargetType.sharedLibrary, "vbe"),
		Config("testsuite", "testsuite.d", artifactDir, srcDir, TargetType.executable),
		Config("fuzzer", "fuzzer.d", artifactDir, srcDir, TargetType.executable),
	];

	bool needsHelp;
	GlobalSettings gs = args.parseSettings(needsHelp, configs);

	if (needsHelp) {
		printHelp;
		return 1;
	}

	return runSelectedConfigs(gs, configs);
}

int runSelectedConfigs(in GlobalSettings gs, in Config[] configs)
{
	MonoTime startTime = currTime;
	scope(exit) gs.printTime("- All configs: %ss", currTime - startTime);

	foreach(configName; gs.configNames)
	{
		Config config = configs.findConfig(configName);

		if (config.targetType == TargetType.unknown) {
			stderr.writeln("Unknown config: ", config.name);
			printConfigs;
			return 1;
		}

		int status = runConfig(gs, config);
		if (status != 0) return status;
	}
	return 0;
}

void printTime(in GlobalSettings gs, string fmt, Duration duration) {
	if (!gs.printTotalTime) return;
	stderr.writefln(fmt, scaledNumberFmt(duration));
}

int runConfig(in GlobalSettings gs, in Config config)
{
	CompileParams params = {
		targetName : config.targetName,
		targetType : config.targetType,
		artifactDir : config.artifactDir,
		srcDir : config.srcDir,
		buildType : gs.buildType,
		compiler : gs.compiler,
		targetOs : gs.targetOs,
		targetArch : gs.targetArch,
		rootFile : config.rootFile,
		archiveName : config.archiveName,
	};

	Job compileJob = gs.makeCompileJob(params);
	JobResult res1 = gs.runJob(compileJob);

	if (res1.status != 0) {
		if (res1.output.canFind("-1073741819")) {
			// This is a link.exe bug, where it crashes when previous compilation was done with ldc2, and old .pdb file is present
			// delete that file and retry
			// Happens to ldc after ldc too
			gs.deletePdbArtifacts(compileJob);
			stderr.writeln("Retrying");
			JobResult retryRes = gs.runJob(compileJob);
			move(/*src*/ retryRes, /*dst*/ res1);
		}
	}

	gs.printTime("- Build: %ss", res1.duration);

	if (res1.status != 0) return res1.status;

	final switch(gs.action)
	{
		case Action.build:
			break;

		case Action.run:
			Job runJob = gs.makeRunJob(res1);
			JobResult res2 = gs.runJob(runJob);
			gs.printTime("- Run: %ss", res2.duration);
			if (res2.status != 0) return res2.status;
			break;

		case Action.pack:
			Job packageJob = gs.makePackageJob(res1);
			JobResult res2 = gs.runJob(packageJob);
			gs.printTime("- Run: %ss", res2.duration);
			if (res2.status != 0) return res2.status;

			break;
	}

	if (gs.removeBuild) {
		gs.deleteArtifacts(compileJob.artifacts);
		gs.deleteArtifacts(compileJob.extraArtifacts);
	}

	return 0;
}

void printHelp() {
	printOptions;
	printConfigs;
}

struct Config
{
	string name;
	string rootFile;
	string artifactDir;
	string srcDir;
	TargetType targetType;
	string targetName;
	string archiveName;

	this(string name, string rootFile, string artifactDir, string srcDir, TargetType targetType, string targetName = null, string archiveName = null) {
		this.name = name;
		this.rootFile = rootFile;
		this.artifactDir = artifactDir;
		this.srcDir = srcDir;
		this.targetType = targetType;
		this.targetName = targetName;
		if (this.targetName == null) this.targetName = this.name;
		if (this.archiveName == null) this.archiveName = this.name;
	}

	bool isValidForTriple(TargetArch arch, TargetOs os) const {
		final switch(arch) with(TargetArch) {
			case x64, arm64:
				if (os == TargetOs.macos && targetType == TargetType.sharedLibrary) return false;
				return true;
			case wasm32:
				final switch(os) with(TargetOs) {
					case windows, linux, macos: assert(0);
					case wasm: return targetType != TargetType.staticLibrary;
					case wasi: return targetType == TargetType.executable;
				}
		}
	}
}

Config findConfig(in Config[] configs, string configName) {
	foreach(conf; configs)
		if (conf.name == configName)
			return conf;
	return Config(configName, null, null, null, TargetType.unknown);
}

struct GlobalSettings
{
	Action action;
	BuildType buildType;
	TargetOs targetOs = hostOs;
	TargetArch targetArch;
	void nodeps() {
		betterc = true;
		nolibc = true;
		customobject = true;
	}
	bool fuzzer;
	bool betterc;
	bool nolibc;
	bool customobject; // Use custom object.d from source/druntime/object.d
	bool color;
	Compiler compiler;
	const(string)[] configNames;
	bool dryRun;
	bool removeBuild;
	bool printCommands;
	bool prettyPrint;
	bool printCallees;
	bool verboseCallees;
	bool printTotalTime;
	bool timeTrace;

	bool isCrossCompiling() const {
		return targetOs != hostOs || targetArch != hostArch;
	}

	bool runWithQemu() const {
		return targetOs == hostOs && targetOs == TargetOs.linux && targetArch != hostArch;
	}
}

void printOptions() {
	stderr.writeln("Usage: builder [options]...");
	stderr.writeln("Options:");
	stderr.writeln("   --action=<action>  Select action [build(default), run, pack]");
	stderr.writeln("            build     Build artifact");
	stderr.writeln("            run       Build and run resulting executable");
	stderr.writeln("            pack      Build artifact and package into a .zip");
	stderr.writeln("   --target=<target>  Select target [windows-x64, linux-x64, macos-x64, wasm32, wasm32-wasi]");
	stderr.writeln("   --build=<type>     Select build type [debug(default), debug-fast, release-fast]");
	stderr.writeln("   --compiler=<name>  Select compiler [dmd, ldc2] (by default dmd is used for debug and ldc2 for release)");
	stderr.writeln("   --config=<name>    Select config. Can be specified multiple times, or comma-separated (--config=a,b,c)");
	stderr.writeln("   --dry-run          Do not run any commands");
	stderr.writeln("   --remove-build     Delete build artifacts after completion. Useful for building only .zip");
	stderr.writeln("   --print-commands   Print commands that are being run");
	stderr.writeln("   --pretty           Enable pretty printing of the commands");
	stderr.writeln("   --print-callees    Print output of callee programs");
	stderr.writeln("   --verbose-callees  Passes verbose flag to called programs");
	stderr.writeln("   --print-total-time Print time of all run commands");
	stderr.writeln("   --fuzzer           Enable fuzzing");
	stderr.writeln("   --no-deps          --betterc + --no-libc + --customobject");
	stderr.writeln("     --betterc        Compile in betterC mode");
	stderr.writeln("     --no-libc        Compile without libc dependency");
	stderr.writeln("     --customobject   Use custom object.d");
	stderr.writeln("   --color            Enable colored output");
	stderr.writeln("-h --help             This help information");
}

void printConfigs() {
	stderr.writeln("Configs:");
	stderr.writeln("            all         Select all configs valid for selected target.");
	stderr.writeln("                        Ignores other config options.");
	stderr.writeln("            nih-cli     Compiler CLI executable (default)");
	stderr.writeln("            nih-static  Compiler static library");
	stderr.writeln("            nih-shared  Compiler dynamic library");
	stderr.writeln("            vbe-static  Backend static library");
	stderr.writeln("            vbe-shared  Backend dynamic library");
	stderr.writeln("            testsuite   Full test suite executable");
}

GlobalSettings parseSettings(string[] args, out bool needsHelp, const(Config)[] configs) {
	import std.getopt : GetoptResult, GetOptException, getopt, arraySep;
	GlobalSettings settings;
	string compiler;
	string target;
	string buildType;

	needsHelp = false;
	GetoptResult optResult;

	arraySep = ",";

	retry_parse_opts:
	try
	{
		optResult = getopt(
			args,
			"action", "", &settings.action,
			"build", "", &buildType,
			"target", "", &target,
			"compiler", "", &compiler,
			"config", "", &settings.configNames,
			"dry-run", "", &settings.dryRun,
			"remove-build", "", &settings.removeBuild,
			"print-commands", "", &settings.printCommands,
			"pretty", "", &settings.prettyPrint,
			"print-callees", "", &settings.printCallees,
			"verbose-callees", "", &settings.verboseCallees,
			"print-total-time", "", &settings.printTotalTime,
			"no-deps", "", &settings.nodeps,
			"fuzzer", "", &settings.fuzzer,
			"betterc", "", &settings.betterc,
			"no-libc", "", &settings.nolibc,
			"customobject", "", &settings.customobject,
			"color", "", &settings.color,
			"time-trace", "", &settings.timeTrace,
		);
	}
	catch(GetOptException e)
	{
		import std.algorithm.mutation : remove;

		stderr.writeln(e.msg);
		needsHelp = true;
		args = args.remove(1);
		goto retry_parse_opts;
	}

	if (args.length > 1) {
		// we have unrecognized options
		needsHelp = true;
		foreach(opt; args[1..$]) {
			stderr.writefln("Unknown option: %s", opt);
		}
	}

	if (!isValidBuildType(buildType)) {
		stderr.writefln("Invalid build type: %s. Supported options: debug, debug-fast, release-fast", buildType);
		needsHelp = true;
		return settings;
	}
	settings.buildType = selectBuildType(buildType);

	switch(target) {
		case "windows-x64":
			settings.targetOs = TargetOs.windows;
			settings.targetArch = TargetArch.x64;
			break;
		case "linux-x64":
			settings.targetOs = TargetOs.linux;
			settings.targetArch = TargetArch.x64;
			break;
		case "linux-arm64":
			settings.targetOs = TargetOs.linux;
			settings.targetArch = TargetArch.arm64;
			break;
		case "macos-x64":
			settings.targetOs = TargetOs.macos;
			settings.targetArch = TargetArch.x64;
			break;
		case "wasm32":
			settings.targetOs = TargetOs.wasm;
			settings.targetArch = TargetArch.wasm32;
			break;
		case "wasm32-wasi":
			settings.targetOs = TargetOs.wasi;
			settings.targetArch = TargetArch.wasm32;
			break;
		case null:
			break;
		default:
			stderr.writefln("Unknown target: %s", target);
			needsHelp = true;
	}

	if (!isValidCompiler(compiler)) {
		stderr.writefln("Invalid compiler name: %s. Supported options: dmd, ldc2", compiler);
		needsHelp = true;
		return settings;
	}
	if (settings.isCrossCompiling && compiler == "dmd") {
		stderr.writefln("dmd cannot cross-compile");
		needsHelp = true;
		return settings;
	}
	settings.compiler = selectCompiler(settings, compiler);

	if (optResult.helpWanted) needsHelp = true;

	if (settings.configNames.canFind("all")) {
		// Select all configs
		settings.configNames = configs
			.filter!(c => c.isValidForTriple(settings.targetArch, settings.targetOs))
			.map!(c => c.name)
			.array;
	} else if (settings.configNames.empty) {
		// Select default config
		settings.configNames ~= configs[0].name;
	} else {
		foreach(name; settings.configNames) {
			if (!configs.map!(c => c.name).canFind(name)) {
				stderr.writeln("Unknown config: ", name);
				needsHelp = true;
				return settings;
			}
		}
	}

	return settings;
}

struct CompileParams
{
	string rootFile;
	string srcDir;
	string artifactDir;
	TargetType targetType;
	BuildType buildType;
	string targetName;
	string archiveName;
	Compiler compiler;
	TargetOs targetOs;
	TargetArch targetArch;

	string makeArtifactPath(string extension) const {
		return artifactDir.buildPath(targetName).setExtension(extension);
	}
}

struct Job {
	CompileParams params;
	string[] args;
	string workDir;
	// When executable is produced it will be a first artifact
	string[] artifacts;
	// Artifacts that are produces by the job, but we don't want to include them into the package
	// Useful to know, so we can delete them
	string[] extraArtifacts;
	// Remove artifacts of previous run before execution
	bool cleanBeforeRun;
	// Always print the output of the command
	bool printOutput;
}

Job makeCompileJob(in GlobalSettings gs, in CompileParams params) {
	import std.path : buildPath;

	string[] artifacts;
	string[] extraArtifacts;

	final switch(params.targetType) with(TargetType) {
		case unknown: assert(false);
		case executable:
			artifacts ~= params.makeArtifactPath(osExeExt[gs.targetOs]);
			if (gs.targetOs == TargetOs.windows) extraArtifacts ~= params.makeArtifactPath(".exp");
			if (gs.targetOs == TargetOs.windows) extraArtifacts ~= params.makeArtifactPath(".ilk");
			break;
		case staticLibrary:
			artifacts ~= params.makeArtifactPath(osStaticLibExt[gs.targetOs]);
			break;
		case sharedLibrary:
			artifacts ~= params.makeArtifactPath(osSharedLibExt[gs.targetOs]);
			if (gs.targetOs == TargetOs.windows) {
				artifacts ~= params.makeArtifactPath(osStaticLibExt[gs.targetOs]); // import .lib
				extraArtifacts ~= params.makeArtifactPath(".exp");
				extraArtifacts ~= params.makeArtifactPath(".ilk");
			}
			break;
	}

	extraArtifacts ~= params.makeArtifactPath(osObjExt[gs.targetOs]);

	Flags flags = selectFlags(gs, params);
	string[] flagsStrings = flagsToStrings(gs, cast(size_t)flags, params);

	flagsStrings ~= gs.makeTargetTripleFlag;

	if (gs.targetOs == TargetOs.windows) {
		if (params.targetType == TargetType.executable || params.targetType == TargetType.sharedLibrary) {
			if (flags & Flags.f_debug_info) {
				artifacts ~= params.makeArtifactPath(osDebugInfoExt[gs.targetOs]); // .pdb file
			}
		}
	}

	string mainFile = buildPath(params.srcDir, params.rootFile);

	string imports = text("-I=", params.srcDir);

	string[] args;
	args ~= compilerExeName[params.compiler];
	args ~= imports;
	args ~= flagsStrings;
	args ~= text("-of=", artifacts[0]);
	args ~= mainFile;

	if (gs.customobject) {
		args ~= buildPath(params.srcDir, "custom_object.d");
	}

	Job job = {
		params : params,
		args : args,
		artifacts : artifacts,
		extraArtifacts : extraArtifacts,
		printOutput : gs.printCallees,
	};
	return job;
}

Job makePackageJob(in GlobalSettings gs, JobResult compileRes) {
	string archiveName = compileRes.job.params.makeArchiveName;
	string archivePath = compileRes.job.params.artifactDir.buildPath(archiveName).setExtension(".zip");

	string[] args;
	args ~= "7z";
	args ~= "a";
	args ~= "-mx9";
	args ~= archivePath;
	args ~= compileRes.job.artifacts;

	// cleanBeforeRun removes old archive. We want to create a new archive, othewise 7z will update existing one
	Job job = { args : args, artifacts : [archivePath], cleanBeforeRun : true, printOutput : gs.printCallees };
	return job;
}

Job makeGitTagJob(in GlobalSettings gs, JobResult res) {
	string[] args = [
		"git",
		"describe",
		"--tags",
		"--match",
		"v*.*.*",
		"--abbrev=9"
	];

	Job job = { args : args, printOutput : gs.printCallees };
	return job;
}

Job makeRunJob(in GlobalSettings gs, JobResult compileRes) {
	final switch(gs.targetOs) with(TargetOs) {
		case windows, linux, macos:
			if (gs.runWithQemu()) return makeRunQemuJob(gs, compileRes);
			return makeRunNativeExecutableJob(gs, compileRes);
		case wasi: return makeRunWasmWasiJob(gs, compileRes);
		case wasm: assert(false, "Cannot run artifact of wasm target");
	}
}

Job makeRunNativeExecutableJob(in GlobalSettings gs, JobResult compileRes) {
	string[] args;
	args ~= compileRes.job.artifacts[0];
	string workDir = compileRes.job.params.artifactDir;
	Job job = { args : args, workDir : workDir, printOutput : true };
	return job;
}

Job makeRunQemuJob(in GlobalSettings gs, JobResult compileRes) {
	string[] args;
	args ~= text("qemu-", archTripleName[gs.targetArch]);
	args ~= compileRes.job.artifacts[0];
	string workDir = compileRes.job.params.artifactDir;
	Job job = { args : args, workDir : workDir, printOutput : true };
	return job;
}

Job makeRunWasmWasiJob(in GlobalSettings gs, JobResult compileRes) {
	string[] args;
	args ~= "wasmtime";
	// enable threads
	args ~= ["--wasi", "threads=y"];
	args ~= compileRes.job.artifacts[0];
	string workDir = compileRes.job.params.artifactDir;
	Job job = { args : args, workDir : workDir, printOutput : true };
	return job;
}

struct JobResult {
	const Job job;
	int status;
	string output;
	Duration duration;
}

JobResult runJob(in GlobalSettings gs, in Job job) {

	if (job.cleanBeforeRun) {
		gs.deleteArtifacts(job.artifacts);
		gs.deleteArtifacts(job.extraArtifacts);
	}

	void printCommand() {
		if (gs.prettyPrint)
			stderr.writefln("> %-(%s\n| %)", job.args);
		else
			stderr.writefln("> %-(%s %)", job.args);
	}

	if (gs.printCommands) printCommand;

	if (gs.dryRun) return JobResult(job, 0);

	MonoTime startTime = currTime;
	import std.process : execute, Config;
	auto result = execute(job.args, null, Config.none, size_t.max, job.workDir);
	MonoTime endTime = currTime;

	void printCalleeOutput() {
		auto stripped = result.output.strip;
		if (stripped.empty) return;
		foreach(line; result.output.lineSplitter.filter!(l => !l.empty)) {
			stderr.writeln("  ", line);
		}
	}

	if (result.status == 0) {
		if (job.printOutput) printCalleeOutput;
	} else {
		if (!gs.printCommands) printCommand; // print command on error if we didn't print it yet
		printCalleeOutput; // always print on error
		stderr.writeln("Command exited with ", result.status);
	}

	return JobResult(job, result.status, result.output.strip, endTime - startTime);
}

void deleteArtifacts(in GlobalSettings gs, in string[] artifacts) {
	import std.file : exists, remove;
	foreach(art; artifacts)
		if (exists(art)) {
			if (gs.printCommands) stderr.writeln("> remove ", art);
			if (!gs.dryRun) remove(art);
		}
}

void deletePdbArtifacts(in GlobalSettings gs, in Job job) {
	import std.file : exists, remove;
	import std.path : extension;
	foreach(art; chain(job.artifacts, job.extraArtifacts))
		if (art.extension == ".pdb")
			if (exists(art)) {
				if (gs.printCommands) stderr.writeln("> remove ", art);
				if (!gs.dryRun) remove(art);
			}
}

string makeCanonicalPath(in string path) {
	import std.array : array;
	import std.path : asAbsolutePath, asNormalizedPath, expandTilde;
	return path.expandTilde.asAbsolutePath.asNormalizedPath.array;
}

string makeArchiveName(in CompileParams params) {
	string buildType = params.makeBuildTypeSuffix;
	return format("%s-%s-%s-%s", params.archiveName, osName[params.targetOs], archName[params.targetArch], buildType);
}

bool isValidCompiler(in string c) {
	return [null, "dmd", "ldc2"].canFind(c);
}

Compiler selectCompiler(in GlobalSettings gs, in string providedCompiler) {
	switch(providedCompiler) {
		case "dmd": return Compiler.dmd;
		case "ldc2": return Compiler.ldc;
		default: break;
	}

	if (gs.isCrossCompiling) {
		return Compiler.ldc;
	}

	if (gs.fuzzer) {
		return Compiler.ldc;
	}

	if (gs.buildType == BuildType.dbg)
		return Compiler.dmd;
	else
		return Compiler.ldc;
}

bool isValidBuildType(in string b) {
	return [null, "debug", "debug-fast", "release-fast"].canFind(b);
}

BuildType selectBuildType(in string providedBuildType) {
	switch(providedBuildType) {
		case null: return BuildType.dbg;
		case "debug": return BuildType.dbg;
		case "debug-fast": return BuildType.dbg_fast;
		case "release-fast": return BuildType.rel_fast;
		default: assert(false);
	}
}

string makeBuildTypeSuffix(in CompileParams params) {
	if (params.buildType == BuildType.rel_fast)
		return "rel";
	else
		return "dbg";
}

Flags selectFlags(in GlobalSettings g, in CompileParams params)
{
	Flags flags = Flags.f_warn_info | Flags.f_msg_columns | Flags.f_msg_gnu | Flags.f_msg_context | Flags.f_compile_imported;

	if (g.isCrossCompiling) {
		flags |= Flags.f_link_internally;
	}

	if (g.verboseCallees) flags |= Flags.f_verbose;
	if (g.betterc) flags |= Flags.f_better_c;
	if (g.fuzzer) flags |= Flags.f_fuzzer;
	if (g.nolibc) flags |= Flags.f_no_libc;
	if (g.color) flags |= Flags.f_msg_color;
	if (g.timeTrace) flags |= Flags.f_time_trace;

	final switch(params.targetType) with(TargetType) {
		case unknown: assert(false);
		case executable:
			flags |= Flags.f_executable;
			break;
		case staticLibrary:
			flags |= Flags.f_static_lib;
			break;
		case sharedLibrary:
			flags |= Flags.f_shared_lib;
			break;
	}

	final switch(params.buildType) with(BuildType) {
		case dbg:
			flags |= Flags.f_debug;
			flags |= Flags.f_debug_info;
			flags |= Flags.f_link_debug_full;
			break;
		case dbg_fast:
			flags |= Flags.f_debug;
			flags |= Flags.f_debug_info;
			flags |= Flags.f_link_debug_full;
			flags |= Flags.f_opt;
			break;
		case rel_fast:
			flags |= Flags.f_release;
			flags |= Flags.f_opt;
			break;
	}

	if (g.compiler == Compiler.ldc) {
		// Enable caching
		flags |= Flags.f_cache;
	}

	return flags;
}

string[] flagsToStrings(in GlobalSettings gs, in size_t bits, in CompileParams params) {
	import core.bitop : bsf;

	string[] flags;
	string[] versions;
	string[] linkerFlags;

	size_t bitscopy = bits;

	while (bitscopy != 0)
	{
		// Extract lowest set isolated bit
		// 111000 -> 001000; 0 -> 0
		const size_t lowestSetBit = bitscopy & -bitscopy;

		final switch(cast(Flags)lowestSetBit) with(Flags) {
			case f_verbose: flags ~= "-v"; break;
			case f_warn_error: flags ~= "-w"; break;
			case f_warn_info: flags ~= "-wi"; break;
			case f_msg_columns: flags ~= "-vcolumns"; break;
			case f_msg_context:
				if (gs.compiler == Compiler.dmd)
					flags ~= "-verrors=context";
				else
					flags ~= "-verrors-context";
				break;
			case f_msg_color: if (gs.compiler == Compiler.dmd) flags ~= "-color"; break;
			case f_better_c: flags ~= "-betterC"; break;
			case f_no_libc:
				versions ~= "NO_DEPS";
				if (gs.targetOs == TargetOs.windows) {
					if (gs.compiler == Compiler.dmd) {
						// ldc need memset and memcpy from those libs
						// Unlike dmd ldc produces compact artifact, so leaving those out is fine
						linkerFlags ~= "/nodefaultlib:libcmt";
						linkerFlags ~= "/nodefaultlib:libvcruntime";
						linkerFlags ~= "/nodefaultlib:oldnames";
					}
				} else if (gs.targetOs == TargetOs.linux || gs.targetOs == TargetOs.macos) {
					if (gs.compiler == Compiler.ldc) {
						// Remove -lrt -ldl -lpthread -lm libraries
						flags ~= "--platformlib=";
					}
				}
				break;
			case f_executable:
				if ((bits & Flags.f_fuzzer) == 0) {
					versions ~= "EXECUTABLE";

					if (gs.targetOs == TargetOs.windows) {
						if (bits & Flags.f_no_libc) {
							linkerFlags ~= "/entry:" ~ osExecutableEntry[gs.targetOs];
						}
						linkerFlags ~= "/subsystem:console";
					} else if (gs.targetOs == TargetOs.linux) {
						if (gs.compiler == Compiler.ldc) {
							if (bits & Flags.f_no_libc) {
								linkerFlags ~= "--entry=" ~ osExecutableEntry[gs.targetOs];
							}
						}
					}
				}
				break;
			case f_static_lib:
				versions ~= "STATIC_LIB";
				if (gs.targetArch != TargetArch.wasm32) {
					flags ~= "-lib";
				}
				break;
			case f_shared_lib:
				if (gs.targetArch != TargetArch.wasm32) {
					flags ~= "-shared";
				}
				if (gs.compiler == Compiler.ldc) {
					flags ~= "-fvisibility=hidden";
					if ((bits & Flags.f_better_c) == 0) {
						flags ~= "-link-defaultlib-shared=false";
					}
				}
				versions ~= "SHARED_LIB";
				if (gs.targetOs == TargetOs.windows) {
					if (bits & Flags.f_no_libc) {
						linkerFlags ~= "/entry:" ~ osSharedLibEntry[gs.targetOs];
					}
				}
				break;
			case f_release: flags ~= "-release"; break;
			case f_debug:
				if (gs.compiler == Compiler.dmd)
					flags ~= "-debug";
				else
					flags ~= "-d-debug";
				break;
			case f_debug_info: flags ~= "-g"; break;
			case f_msg_gnu: flags ~= "-verror-style=gnu"; break;
			case f_checkaction_halt: flags ~= "-checkaction=halt"; break;
			case f_link_internally:
				if (gs.compiler == Compiler.ldc) flags ~= "-link-internally";
				break;
			case f_opt:
				if (gs.compiler == Compiler.dmd)
					flags ~= "-O";
				else {
					flags ~= ["-O3", "-boundscheck=off", "-enable-inlining"]; // "-linkonce-templates"
					if (gs.targetArch == TargetArch.x64) {
						flags ~= "-mcpu=x86-64-v3";
					}
					if (gs.targetOs == TargetOs.windows || gs.targetOs == TargetOs.linux) {
						flags ~= "-flto=full";
					}
					if (gs.targetOs == TargetOs.windows) {
						if ((bits & Flags.f_better_c) == 0) {
							flags ~= "-defaultlib=phobos2-ldc-lto,druntime-ldc-lto";
						}
					}
				}
				break;
			case f_link_debug_full:
				if (gs.targetOs == TargetOs.windows) linkerFlags ~= "/DEBUG:FULL";
				break;
			case f_compile_imported:
				flags ~= "-i";
				break;
			case f_coverage:
				flags ~= "-cov";
				break;
			case f_fuzzer:
				versions ~= "FUZZER";
				flags ~= "-fsanitize=fuzzer";
				flags ~= "-fsanitize=address";
				break;

			case f_time_trace:
				if (gs.compiler == Compiler.ldc) {
					flags ~= "-ftime-trace";
				}
				break;

			case f_cache:
				if (gs.compiler != Compiler.ldc) break;
				string cacheDir = params.artifactDir.buildPath("cache");
				flags ~= format("--cache=%s", cacheDir);
				break;
		}

		// Disable lowest set isolated bit
		// 111000 -> 110000
		bitscopy ^= lowestSetBit;
	}

	if ((bits & Flags.f_no_libc) == 0) {
		versions ~= "VANILLA_D";
	}

	final switch(gs.targetOs) with(TargetOs) {
		case windows, linux, wasi: break;
		case macos: {
			if (gs.targetArch == TargetArch.x64) {
				linkerFlags ~= "-arch";
				linkerFlags ~= "x86_64";
				linkerFlags ~= "-platform_version";
				linkerFlags ~= "macos";
				linkerFlags ~= "11.0.0";
				linkerFlags ~= "11.7";
			}
			break;
		}
		case wasm: {
			linkerFlags ~= "--no-entry";
			break;
		}
	}

	final switch(gs.targetArch) with(TargetArch) {
		case x64, arm64: break;
		case wasm32: {
			linkerFlags ~= "-allow-undefined";

			// Needed for atomic operations in threads
			linkerFlags ~= "--shared-memory";

			// Without this other threads do not see any changes to memory
			linkerFlags ~= "--import-memory";

			// Without export WASI functions do not work
			// Memory is exported by default, unless --import-memory is specified
			linkerFlags ~= "--export-memory";

			// --initial-memory=<size> can be used to control initial memory size
			// linkerFlags ~= "--initial-memory=2228224";

			enum MiB = 1024 * 1024;
			enum MAX_MEM = 64 * MiB;

			// When using --shared-memory, the memory cannot grow past its max size
			// By default max size is equal to initial size
			// so set it to something enough for the whole execution (64MiB)
			// See: https://github.com/WebAssembly/threads/blob/main/proposals/threads/Overview.md#resizing
			// (memory (;0;) 17 1024 shared)
			//                |    |
			//                |    max size (64KiB pages)
			//                initial size (64KiB pages)
			// in bytes
			linkerFlags ~= format("--max-memory=%s", MAX_MEM);

			flags ~= "-mattr=+bulk-memory,+atomics";
			flags ~= "-fvisibility=hidden";
			break;
		}
	}

	foreach(flag; linkerFlags)
		flags ~= text("-L", flag);

	foreach(ver; versions) {
		if (gs.compiler == Compiler.dmd) flags ~= text("-version=", ver);
		if (gs.compiler == Compiler.ldc) flags ~= text("-d-version=", ver);
	}

	return flags;
}

enum TargetType : ubyte {
	unknown,
	executable,
	staticLibrary,
	sharedLibrary,
}

enum Action : ubyte {
	build,
	run,
	pack,
}

enum BuildType : ubyte {
	dbg,
	dbg_fast,
	rel_fast,
}

enum Compiler : ubyte {
	dmd,
	ldc
}

immutable string[2] compilerExeName = [
	Compiler.dmd : "dmd",
	Compiler.ldc : "ldc2",
];

enum Flags : uint {
	f_verbose            = 1 << 0,
	f_no_libc            = 1 << 1,
	f_better_c           = 1 << 2,
	f_executable         = 1 << 3,
	f_static_lib         = 1 << 4,
	f_shared_lib         = 1 << 5,
	f_warn_info          = 1 << 6,
	f_warn_error         = 1 << 7,
	f_release            = 1 << 8,
	f_debug              = 1 << 9,
	f_debug_info         = 1 << 10,
	f_msg_columns        = 1 << 11,
	f_msg_context        = 1 << 12,
	f_msg_color          = 1 << 13,
	f_msg_gnu            = 1 << 14,
	f_checkaction_halt   = 1 << 15,
	f_link_internally    = 1 << 16,
	f_opt                = 1 << 17,
	f_link_debug_full    = 1 << 18,
	f_compile_imported   = 1 << 19,
	f_coverage           = 1 << 20,
	f_fuzzer             = 1 << 21,
	f_time_trace         = 1 << 22,
	f_cache              = 1 << 23,
}

enum TargetOs : ubyte {
	windows,
	linux,
	macos,
	wasm,
	wasi,
}

version(Windows) {
	enum TargetOs hostOs = TargetOs.windows;
} else version(linux) {
	enum TargetOs hostOs = TargetOs.linux;
} else version(OSX) {
	enum TargetOs hostOs = TargetOs.macos;
} else version(WASI) {
	enum TargetOs hostOs = TargetOs.wasi;
} else version(WebAssembly) {
	enum TargetOs hostOs = TargetOs.wasm;
} else static assert(false, "Unsupported OS");

immutable string[5] osTripleName = [
	TargetOs.windows : "windows-msvc",
	TargetOs.linux : "linux-gnu",
	TargetOs.macos : "apple-darwin",
	TargetOs.wasm : "webassembly",
	TargetOs.wasi : "wasi",
];

immutable string[5] osName = [
	TargetOs.windows : "windows",
	TargetOs.linux : "linux",
	TargetOs.macos : "macos",
	TargetOs.wasm : "wasm",
	TargetOs.wasi : "wasi",
];

immutable string[5] osExeExt = [
	TargetOs.windows : ".exe",
	TargetOs.linux : "",
	TargetOs.macos : "",
	TargetOs.wasm : ".wasm",
	TargetOs.wasi : ".wasm",
];

immutable string[5] osObjExt = [
	TargetOs.windows : ".obj",
	TargetOs.linux : ".o",
	TargetOs.macos : ".o",
	TargetOs.wasm : ".o",
	TargetOs.wasi : ".o",
];

immutable string[5] osStaticLibExt = [
	TargetOs.windows : ".lib",
	TargetOs.linux : ".a",
	TargetOs.macos : ".a",
	TargetOs.wasm : ".a",
	TargetOs.wasi : ".a",
];

immutable string[5] osSharedLibExt = [
	TargetOs.windows : ".dll",
	TargetOs.linux : ".so",
	TargetOs.macos : ".dylib",
	TargetOs.wasm : ".wasm",
	TargetOs.wasi : ".wasm",
];

immutable string[5] osDebugInfoExt = [
	TargetOs.windows : ".pdb",
	TargetOs.linux : "",
	TargetOs.macos : "",
	TargetOs.wasm : "",
	TargetOs.wasi : "",
];

immutable string[5] osExecutableEntry = [
	TargetOs.windows : "exe_main",
	TargetOs.linux : "exe_main",
	TargetOs.macos : "exe_main",
	TargetOs.wasm : "_entry",
	TargetOs.wasi : "_entry",
];

immutable string[5] osSharedLibEntry = [
	TargetOs.windows : "DllMain",
	TargetOs.linux : "shared_main",
	TargetOs.macos : "shared_main",
	TargetOs.wasm : "shared_main",
	TargetOs.wasi : "shared_main",
];


enum TargetArch : ubyte {
	x64,
	arm64,
	wasm32,
}

immutable string[3] archName = [
	TargetArch.x64 : "x64",
	TargetArch.arm64 : "arm64",
	TargetArch.wasm32 : "wasm32",
];

version(X86_64) {
	enum TargetArch hostArch = TargetArch.x64;
} else version(AArch64) {
	enum TargetArch hostArch = TargetArch.arm64;
} else version(WebAssembly) {
	enum TargetArch hostArch = TargetArch.wasm32;
} else static assert(false, "Unsupported architecture");

immutable string[3] archTripleName = [
	TargetArch.x64 : "x86_64",
	TargetArch.arm64 : "aarch64",
	TargetArch.wasm32 : "wasm32",
];

string makeTargetTripleFlag(in GlobalSettings gs) {
	if (gs.targetArch == TargetArch.x64 && gs.targetOs == hostOs) return "-m64";
	return text("-mtriple=", archTripleName[gs.targetArch], "-", osTripleName[gs.targetOs]);
}



MonoTime currTime() { return MonoTime.currTime(); }

/// Use 'i' format char to get binary prefixes (like Ki, instead of K), only for integers
/// Use '#' flag to get greek letter in the output (not compatible with 'i')
struct ScaledNumberFmt(T) {
	import std.algorithm : min, max;
	import std.format : formattedWrite, FormatSpec;
	T value;
	void toString(scope void delegate(const(char)[]) sink, const ref FormatSpec!char fmt) const {
		if (fmt.spec == 'i') {
			// Use binary prefixes instead of decimal prefixes
			long intVal = cast(long)value;
			int scale = calcScale2(intVal);
			double scaledValue = scaled2(value, scale);
			int digits = numDigitsInNumber10(scaledValue);
			string prefix = scalePrefixesAscii[scaleToScaleIndex2(scale)]; // length is 1 or 0
			int width = max(fmt.width - (cast(int)prefix.length * 2), 0); // account for 'i' prefix
			int precision = max(min(3-digits, fmt.precision), 0); // gives 0 or 1
			string fmtString = (scale == 0) ? "%*.*f%s" : "%*.*f%si";
			sink.formattedWrite(fmtString, width, precision, scaledValue, prefix);
		} else {
			int scale = calcScale10(value);
			auto scaledValue = scaled10(value, -scale);
			int digits = numDigitsInNumber10(scaledValue);
			immutable string[] prefixes = (fmt.flHash) ? scalePrefixesGreek : scalePrefixesAscii;
			string prefix = prefixes[scaleToScaleIndex10(scale)]; // length is 1 or 0
			int width = max(fmt.width - cast(int)prefix.length, 0);
			int precision = max(min(3-digits, fmt.precision), 0); // gives 0 or 1
			sink.formattedWrite("%*.*f%s", width, precision, scaledValue, prefix);
		}
	}
}

auto scaledNumberFmt(T)(T value) {
	return ScaledNumberFmt!T(value);
}

auto scaledNumberFmt(Duration value, double scale = 1) {
	double seconds = value.total!"nsecs" / 1_000_000_000.0;
	return ScaledNumberFmt!double(seconds * scale);
}

// -30 .. 30, with step of 3. Or -10 to 10 with step of 1
immutable string[] scalePrefixesAscii = ["q","r","y","z","a","f","p","n","u","m","","K","M","G","T","P","E","Z","Y","R","Q"];
immutable string[] scalePrefixesGreek = ["q","r","y","z","a","f","p","n","µ","m","","K","M","G","T","P","E","Z","Y","R","Q"];
enum NUM_SCALE_PREFIXES = 10;
enum MIN_SCALE_PREFIX = -30;
enum MAX_SCALE_PREFIX = 30;


int numDigitsInNumber10(Num)(const Num val) {
	import std.math: abs, round;
	ulong absVal = cast(ulong)val.abs.round;
	int numDigits = 1;

	while (absVal >= 10) {
		absVal /= 10;
		++numDigits;
	}

	return numDigits;
}

private int signum(T)(const T x) pure nothrow {
	return (x > 0) - (x < 0);
}

/// Returns number in range of [-30; 30]
int calcScale10(Num)(Num val) {
	import std.math: abs, round, log10;

	// cast to double is necessary in case of long.min, which overflows integral abs
	auto lg = log10(abs(cast(double)val));

	// handle very small values and zero
	if (lg == -double.infinity) return 0;

	double absLog = abs(lg);
	int scale = cast(int)(round(absLog/3.0))*3;

	int logSign = signum(lg);
	int clampedScale = scale * logSign;

	// we want
	//  0.9994 to be formatted as 999m
	//  0.9995 to be formatted as 1.0
	//  0.9996 to be formatted as 1.0
	if (abs(scaled10(val, -clampedScale)) < 0.9995) clampedScale -= 3;

	if (clampedScale < MIN_SCALE_PREFIX)
		clampedScale = 0; // prevent zero, or values smaller that min scale to display with min scale
	else if (clampedScale > MAX_SCALE_PREFIX)
		clampedScale = MAX_SCALE_PREFIX;

	return clampedScale;
}

/// Returns number in range of [0; 100]
int calcScale2(Num)(Num val) {
	import std.math: abs, round, log2;

	auto lg = log2(cast(double)abs(val));
	double absLog = abs(lg);

	int scale = cast(int)(round(absLog/10.0))*10;

	int logSign = signum(lg);
	int clampedScale = scale * logSign;

	// we want
	//  0.9994 to be formatted as 999m
	//  0.9995 to be formatted as 1.0
	//  0.9996 to be formatted as 1.0
	if (abs(scaled2(val, clampedScale)) < 0.9995) clampedScale -= 10;

	if (clampedScale < 0)
		clampedScale = 0; // negative scale should not happen for binary numbers
	else if (clampedScale > MAX_SCALE_PREFIX)
		clampedScale = MAX_SCALE_PREFIX;

	return clampedScale;
}

int scaleToScaleIndex10(int scale) {
	return scale / 3 + NUM_SCALE_PREFIXES; // -30...30 -> -10...10 -> 0...20
}

int scaleToScaleIndex2(int scale) {
	return scale / 10 + NUM_SCALE_PREFIXES; // -100...100 -> -10...10 -> 0...20
}

double scaled10(Num)(Num num, int scale) {
	import std.math: pow;
	return num * pow(10.0, scale);
}

double scaled2(Num)(Num num, int scale) {
	double divisor = 1 << scale;
	return num / divisor;
}
