/// Copyright: Copyright (c) 2022 Andrey Penechko
/// License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
/// Authors: Andrey Penechko

// Notes:
// DMD does not produce .lib and .exp files if program contains no symbols marked as `export`
// When previous build was done with different compiler, .pdb files can confuse linker making it exit with an error.
module builder;

import std.algorithm : filter, joiner, canFind, map;
import std.range : empty, array, chain;
import std.file : thisExePath;
import std.path : dirName, buildPath, setExtension;
import std.stdio;
import std.string : format, lineSplitter;

int main(string[] args)
{
	bool needsHelp;
	GlobalSettings gs = args.parseSettings(needsHelp);

	if (needsHelp) {
		printHelp;
		return 1;
	}

	string artifactDir = thisExePath.dirName.dirName.buildPath("bin").makeCanonicalPath;
	string srcDir = thisExePath.dirName.dirName.buildPath("source").makeCanonicalPath;

	auto nihcli  = Config("nihcli",  "main.d",   artifactDir, srcDir, TargetType.executable, "nih");
	auto nihslib = Config("nihslib", "libnih.d", artifactDir, srcDir, TargetType.staticLibrary);
	auto nihdlib = Config("nihdlib", "libnih.d", artifactDir, srcDir, TargetType.dynamicLibrary);
	auto vbeslib = Config("vbeslib", "libvbe.d", artifactDir, srcDir, TargetType.staticLibrary);
	auto vbedlib = Config("vbedlib", "libvbe.d", artifactDir, srcDir, TargetType.dynamicLibrary);
	auto devtest = Config("devtest", "main.d",   artifactDir, srcDir, TargetType.executable);
	auto test    = Config("test",    "main.d",   artifactDir, srcDir, TargetType.executable);

	Config[] configs = [nihcli, nihslib, nihdlib, vbeslib, vbedlib, devtest, test];

	gs.setDefaultConfigs(configs);

	return selectAndRunConfigs(gs, configs);
}

int selectAndRunConfigs(in GlobalSettings gs, in Config[] configs)
{
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

int runConfig(in GlobalSettings gs, in Config config)
{
	CompileParams params = {
		targetName : config.targetName,
		targetType : config.targetType,
		artifactDir : config.artifactDir,
		srcDir : config.srcDir,
		buildType : gs.buildType,
		compiler : gs.compiler,
		rootFile : config.rootFile,
	};

	auto job = gs.makeCompileJob(params);
	JobResult res1 = gs.runJob(job);

	if (res1.status != 0) {
		if (gs.compiler == "dmd" && res1.output.canFind("-1073741819")) {
			// This a link.exe bug, where it crashes when previous compilation was done with ldc2, and old .pdb file is present
			// delete that file and retry
			gs.deletePdbArtifacts(job);
			stderr.writeln("Retrying");
			JobResult retryRes = gs.runJob(job);
			res1.status = retryRes.status;
		}
	}

	if (res1.status != 0) return res1.status;

	if (gs.action == Action.pack) {
		auto packageJob = makePackageJob(res1);
		JobResult res2 = gs.runJob(packageJob);
		if (res2.status != 0) return res2.status;
	}

	if (gs.action == Action.pack && gs.removeBuild) {
		gs.deleteArtifacts(job);
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

	this(string name, string rootFile, string artifactDir, string srcDir, TargetType targetType, string targetName = null) {
		this.name = name;
		this.rootFile = rootFile;
		this.artifactDir = artifactDir;
		this.srcDir = srcDir;
		this.targetType = targetType;
		this.targetName = targetName;
		if (this.targetName == null) this.targetName = this.name;
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
	string compiler;
	const(string)[] configNames;
	bool dryRun;
	bool removeBuild;
	bool printCommands;
	bool printCallees;
	bool verboseCallees;

	void setDefaultConfigs(in Config[] configs) {
		if (configNames.canFind("all")) {
			configNames = configs.map!(c => c.name).array;
		} else if (configNames.empty) {
			configNames ~= configs[0].name;
		}
	}
}

void printOptions() {
	stderr.writeln("Usage: build <command> [options]...");
	stderr.writeln("Options:");
	stderr.writeln("   --action=<action>  Select action [build(default), package]");
	stderr.writeln("               build  Build artifact");
	stderr.writeln("                pack  Build artifact and package into a .zip");
	stderr.writeln("   --build=<type>     Select build type [debug(default), debug-fast, release-fast]");
	stderr.writeln("   --compiler=<name>  Select compiler [dmd, ldc2] (by default dmd is used for debug and ldc2 for release)");
	stderr.writeln("   --config=<name>    Select config. Can be specified multiple times, or comma-separated (--config=a,b,c)");
	stderr.writeln("   --dry-run          Do not run any commands");
	stderr.writeln("   --remove-build     Delete build artifacts after completion. Useful for building only .zip");
	stderr.writeln("   --print-commands   Print commands that are being run");
	stderr.writeln("   --print-callees    Print output of callee programs");
	stderr.writeln("   --verbose-callees  Passes verbose flag to called programs");
	stderr.writeln("-h --help             This help information");
}

void printConfigs() {
	stderr.writeln("Configs:");
	stderr.writeln("                 all  Select all configs. Ignores other config options.");
	stderr.writeln("              nihcli  Compiler CLI executable (default)");
	stderr.writeln("             nihslib  Compiler static library");
	stderr.writeln("             nihdlib  Compiler dynamic library");
	stderr.writeln("             vbeslib  Backend static library");
	stderr.writeln("             vbedlib  Backend dynamic library");
	stderr.writeln("             devtest  Single test executable");
	stderr.writeln("                test  Full test suite executable");
}

GlobalSettings parseSettings(string[] args, out bool needsHelp) {
	import std.getopt : GetoptResult, GetOptException, getopt, arraySep;
	GlobalSettings settings;
	string compiler;
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
			"compiler", "", &compiler,
			"config", "", &settings.configNames,
			"dry-run", "", &settings.dryRun,
			"remove-build", "", &settings.removeBuild,
			"print-commands", "", &settings.printCommands,
			"print-callees", "", &settings.printCallees,
			"verbose-callees", "", &settings.verboseCallees,
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

	if (!isValidCompiler(compiler)) {
		stderr.writefln("Invalid compiler name (%s). Supported options: dmd, ldc2", compiler);
		needsHelp = true;
		return settings;
	}

	settings.compiler = selectCompiler(settings, compiler);

	if (!isValidBuildType(buildType)) {
		stderr.writefln("Invalid build type (%s). Supported options: debug, debug-fast, release-fast", buildType);
		needsHelp = true;
		return settings;
	}

	settings.buildType = selectBuildType(buildType);

	if (optResult.helpWanted) needsHelp = true;

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
	string compiler;

	string makeArtifactPath(string extension) const {
		return artifactDir.buildPath(targetName).setExtension(extension);
	}
}

struct Job {
	CompileParams params;
	string command;
	string[] artifacts;
	// Artifacts that are produces by the job, but we don't want to include them into the package
	// Useful to know, so we can delete them
	string[] extraArtifacts;
	// Remove artifacts of previous run before execution
	bool cleanBeforeRun;
}

Job makeCompileJob(in GlobalSettings g, in CompileParams params) {
	import std.path : buildPath;
	import std.conv : text;

	string[] artifacts;
	string[] extraArtifacts;

	final switch(params.targetType) with(TargetType) {
		case unknown: assert(false);
		case executable:
			artifacts ~= params.makeArtifactPath(exeExt);
			version(Windows) extraArtifacts ~= params.makeArtifactPath(".exp");
			version(Windows) extraArtifacts ~= params.makeArtifactPath(".ilk");
			break;
		case staticLibrary:
			artifacts ~= params.makeArtifactPath(slibExt);
			break;
		case dynamicLibrary:
			artifacts ~= params.makeArtifactPath(dlibExt);
			version(Windows) {
				artifacts ~= params.makeArtifactPath(slibExt); // import .lib
				extraArtifacts ~= params.makeArtifactPath(".exp");
				extraArtifacts ~= params.makeArtifactPath(".ilk");
			}
			break;
	}

	extraArtifacts ~= params.makeArtifactPath(objExt);

	Flags flags = selectFlags(g, params);
	string[] flagsStrings = flagsToStrings(cast(size_t)flags, params.compiler);

	version(Windows) {
		if (params.targetType == TargetType.executable || params.targetType == TargetType.dynamicLibrary) {
			if (flags & Flags.f_debug_info) {
				artifacts ~= params.makeArtifactPath(dbiExt); // .pdb file
			}
		}
	}

	string mainFile = buildPath(params.srcDir, params.rootFile);

	string imports = text("-I=", params.srcDir);

	string command = format(
		"%s %s %-(-%s %) -of=%s -i %s",
		params.compiler, imports, flagsStrings, artifacts[0], mainFile);

	Job job = { params : params, command : command, artifacts : artifacts, extraArtifacts : extraArtifacts };
	return job;
}

Job makePackageJob(JobResult res) {
	string packageName = res.job.params.makePackageName;
	string archiveName = res.job.params.artifactDir.buildPath(packageName).setExtension(".zip");

	string command = format(
		"7z a -mx9 %s %-(%s %)",
		archiveName, res.job.artifacts);

	// cleanBeforeRun removes old archive, because 7z will update existing archive
	Job job = { command : command, artifacts : [archiveName], cleanBeforeRun : true };
	return job;
}

struct JobResult {
	const Job job;
	int status;
	string output;
}

JobResult runJob(in GlobalSettings gs, in Job job) {

	if (job.cleanBeforeRun) gs.deleteArtifacts(job);

	void printCommand() {
		stderr.writeln("> ", job.command);
	}

	if (gs.printCommands) printCommand;

	if (gs.dryRun) return JobResult(job, 0);

	import std.process : executeShell;
	auto result = executeShell(job.command);

	void printCalleeOutput() {
		stderr.writeln(result.output.lineSplitter.filter!(l => !l.empty).joiner("\n"));
	}

	if (result.status == 0) {
		if (gs.printCallees) printCalleeOutput;
	} else {
		if (!gs.printCommands) printCommand; // print command on error if we didn't print it yet
		printCalleeOutput; // always print on error
		return JobResult(job, result.status, result.output);
	}

	return JobResult(job, 0);
}

void deleteArtifacts(in GlobalSettings gs, in Job job) {
	import std.file : exists, remove;
	foreach(art; chain(job.artifacts, job.extraArtifacts))
		if (exists(art)) {
			if (gs.printCommands) stderr.writeln("> remove ", art);
			remove(art);
		}
}

void deletePdbArtifacts(in GlobalSettings gs, in Job job) {
	import std.file : exists, remove;
	import std.path : extension;
	foreach(art; chain(job.artifacts, job.extraArtifacts))
		if (art.extension == ".pdb")
			if (exists(art)) {
				if (gs.printCommands) stderr.writeln("> remove ", art);
				remove(art);
			}
}

string makeCanonicalPath(in string path) {
	import std.array : array;
	import std.path : asAbsolutePath, asNormalizedPath, expandTilde;
	return path.expandTilde.asAbsolutePath.asNormalizedPath.array;
}

string makePackageName(in CompileParams params) {
	static const archName = "x64";
	string buildType = params.makeBuildTypeSuffix;
	return format("%s-%s-%s-%s", params.targetName, osName, archName, buildType);
}

bool isValidCompiler(in string c) {
	return [null, "dmd", "ldc2"].canFind(c);
}

string selectCompiler(in GlobalSettings g, in string providedCompiler) {
	if (providedCompiler) return providedCompiler;

	if (g.buildType == BuildType.dbg)
		return "dmd";
	else
		return "ldc2";
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
	Flags flags = Flags.f_m64 | Flags.f_warn_info | Flags.f_msg_columns | Flags.f_msg_gnu | Flags.f_msg_context | Flags.f_link_internally;

	//flags |= Flags.f_better_c;

	if (g.verboseCallees) flags |= Flags.f_verbose;

	final switch(params.targetType) with(TargetType) {
		case unknown: assert(false);
		case executable:
			break;
		case staticLibrary:
			flags |= Flags.f_static_lib;
			break;
		case dynamicLibrary:
			flags |= Flags.f_dynamic_lib;
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

	return flags;
}

string[] flagsToStrings(size_t bits, in string compiler) {
	import core.bitop : bsf;

	string[] flags;

	while (bits != 0)
	{
		// Extract lowest set isolated bit
		// 111000 -> 001000; 0 -> 0
		size_t lowestSetBit = bits & -bits;

		final switch(cast(Flags)lowestSetBit) with(Flags) {
			case f_verbose: flags ~= "v"; break;
			case f_warn_error: flags ~= "w"; break;
			case f_warn_info: flags ~= "wi"; break;
			case f_msg_columns: flags ~= "vcolumns"; break;
			case f_msg_context:
				if (compiler == "dmd")
					flags ~= "verrors=context";
				else
					flags ~= "verrors-context";
				break;
			case f_better_c: flags ~= "betterC"; break;
			case f_static_lib: flags ~= "lib"; break;
			case f_dynamic_lib:
				flags ~= "shared";
				if (compiler == "ldc2") {
					flags ~= ["fvisibility=hidden", "link-defaultlib-shared=false"];
				}
				break;
			case f_release: flags ~= "release"; break;
			case f_debug:
				if (compiler == "dmd")
					flags ~= "debug";
				else
					flags ~= "d-debug";
				break;
			case f_debug_info: flags ~= "g"; break;
			case f_msg_gnu: flags ~= "verror-style=gnu"; break;
			case f_checkaction_halt: flags ~= "checkaction=halt"; break;
			case f_m64: flags ~= "m64"; break;
			case f_link_internally:
				version(Windows) if (compiler == "ldc2") flags ~= "link-internally";
				break;
			case f_opt:
				if (compiler == "dmd")
					flags ~= "O";
				else
					flags ~= ["O3", "mcpu=x86-64-v3", "boundscheck=off", "enable-inlining", "flto=full", "linkonce-templates", "defaultlib=phobos2-ldc-lto,druntime-ldc-lto"];
				break;
			case f_link_debug_full:
				version(Windows) flags ~= "L/DEBUG:FULL";
				break;
		}

		// Disable lowest set isolated bit
		// 111000 -> 110000
		bits ^= lowestSetBit;
	}
	return flags;
}

version(Windows) {
	const exeExt = ".exe";
	const objExt = ".obj";
	const slibExt = ".lib";
	const dlibExt = ".dll";
	const dbiExt = ".pdb";
	const osName = "windows";
} else version(linux) {
	const exeExt = "";
	const objExt = ".o";
	const slibExt = ".a";
	const dlibExt = ".so";
	const dbiExt = "";
	const osName = "linux";
} else version(OSX) {
	const exeExt = "";
	const objExt = ".o";
	const slibExt = ".a";
	const dlibExt = ".dylib";
	const dbiExt = "";
	const osName = "macos";
} else static assert(false, "Unsupported OS");

enum TargetType : ubyte {
	unknown,
	executable,
	staticLibrary,
	dynamicLibrary,
}

enum Action : ubyte {
	build,
	pack,
}

enum BuildType : ubyte {
	dbg,
	dbg_fast,
	rel_fast,
}

enum Os : ubyte {
	windows,
	linux,
	macos,
}

enum Compiler : ubyte {
	autoselect, // based on Optimization
	dmd,
	ldc
}

enum Flags : uint {
	f_verbose            = 1 << 0,
	f_better_c           = 1 << 1,
	f_static_lib         = 1 << 2,
	f_dynamic_lib        = 1 << 3,
	f_warn_info          = 1 << 4,
	f_warn_error         = 1 << 5,
	f_release            = 1 << 6,
	f_debug              = 1 << 7,
	f_debug_info         = 1 << 8,
	f_msg_columns        = 1 << 9,
	f_msg_context        = 1 << 10,
	f_msg_gnu            = 1 << 11,
	f_checkaction_halt   = 1 << 12,
	f_m64                = 1 << 13,
	f_link_internally    = 1 << 14,
	f_opt                = 1 << 15,
	f_link_debug_full    = 1 << 16,
}
