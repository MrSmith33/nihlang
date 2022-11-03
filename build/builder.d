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
	string artifactDir = thisExePath.dirName.dirName.buildPath("bin").makeCanonicalPath;
	string srcDir = thisExePath.dirName.dirName.buildPath("source").makeCanonicalPath;

	auto nihcli  = Config("nih-cli",    "nihcli.d", artifactDir, srcDir, TargetType.executable, "nih");
	auto nihslib = Config("nih-static", "libnih.d", artifactDir, srcDir, TargetType.staticLibrary, "nih");
	auto nihdlib = Config("nih-shared", "libnih.d", artifactDir, srcDir, TargetType.dynamicLibrary, "nih");
	auto vbeslib = Config("vbe-static", "libvbe.d", artifactDir, srcDir, TargetType.staticLibrary, "vbe");
	auto vbedlib = Config("vbe-shared", "libvbe.d", artifactDir, srcDir, TargetType.dynamicLibrary, "vbe");
	auto testone = Config("testone",   "testone.d", artifactDir, srcDir, TargetType.executable);
	auto test    = Config("test",         "test.d", artifactDir, srcDir, TargetType.executable);

	Config[] configs = [nihcli, nihslib, nihdlib, vbeslib, vbedlib, testone, test];

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
		archiveName : config.archiveName,
	};

	Job compileJob = gs.makeCompileJob(params);
	JobResult res1 = gs.runJob(compileJob);

	if (res1.status != 0) {
		if (gs.compiler == "dmd" && res1.output.canFind("-1073741819")) {
			// This is a link.exe bug, where it crashes when previous compilation was done with ldc2, and old .pdb file is present
			// delete that file and retry
			gs.deletePdbArtifacts(compileJob);
			stderr.writeln("Retrying");
			JobResult retryRes = gs.runJob(compileJob);
			res1.status = retryRes.status;
		}
	}

	if (res1.status != 0) return res1.status;

	final switch(gs.action)
	{
		case Action.build:
			break;

		case Action.run:
			Job runJob = gs.makeRunJob(res1);
			JobResult res2 = gs.runJob(runJob);
			if (res2.status != 0) return res2.status;
			break;

		case Action.pack:
			Job packageJob = gs.makePackageJob(res1);
			JobResult res2 = gs.runJob(packageJob);
			if (res2.status != 0) return res2.status;

			break;
	}

	if (gs.removeBuild) {
		gs.deleteArtifacts(compileJob);
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
	bool betterc;
	string compiler;
	const(string)[] configNames;
	bool dryRun;
	bool removeBuild;
	bool printCommands;
	bool prettyPrint;
	bool printCallees;
	bool verboseCallees;
}

void printOptions() {
	stderr.writeln("Usage: builder [options]...");
	stderr.writeln("Options:");
	stderr.writeln("   --action=<action>  Select action [build(default), run, pack]");
	stderr.writeln("            build     Build artifact");
	stderr.writeln("            run       Build and run resulting executable");
	stderr.writeln("            pack      Build artifact and package into a .zip");
	stderr.writeln("   --build=<type>     Select build type [debug(default), debug-fast, release-fast]");
	stderr.writeln("   --compiler=<name>  Select compiler [dmd, ldc2] (by default dmd is used for debug and ldc2 for release)");
	stderr.writeln("   --config=<name>    Select config. Can be specified multiple times, or comma-separated (--config=a,b,c)");
	stderr.writeln("   --dry-run          Do not run any commands");
	stderr.writeln("   --remove-build     Delete build artifacts after completion. Useful for building only .zip");
	stderr.writeln("   --print-commands   Print commands that are being run");
	stderr.writeln("   --pretty           Enable pretty printing of the commands");
	stderr.writeln("   --print-callees    Print output of callee programs");
	stderr.writeln("   --verbose-callees  Passes verbose flag to called programs");
	stderr.writeln("   --betterc          Compile in betterC mode");
	stderr.writeln("-h --help             This help information");
}

void printConfigs() {
	stderr.writeln("Configs:");
	stderr.writeln("            all         Select all configs. Ignores other config options.");
	stderr.writeln("            nih-cli     Compiler CLI executable (default)");
	stderr.writeln("            nih-static  Compiler static library");
	stderr.writeln("            nih-shared  Compiler dynamic library");
	stderr.writeln("            vbe-static  Backend static library");
	stderr.writeln("            vbe-shared  Backend dynamic library");
	stderr.writeln("            testone     Single test executable");
	stderr.writeln("            test        Full test suite executable");
}

GlobalSettings parseSettings(string[] args, out bool needsHelp, const(Config)[] configs) {
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
			"pretty", "", &settings.prettyPrint,
			"print-callees", "", &settings.printCallees,
			"verbose-callees", "", &settings.verboseCallees,
			"betterc", "", &settings.betterc,
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

	if (!isValidCompiler(compiler)) {
		stderr.writefln("Invalid compiler name: %s. Supported options: dmd, ldc2", compiler);
		needsHelp = true;
		return settings;
	}

	settings.compiler = selectCompiler(settings, compiler);

	if (!isValidBuildType(buildType)) {
		stderr.writefln("Invalid build type: %s. Supported options: debug, debug-fast, release-fast", buildType);
		needsHelp = true;
		return settings;
	}

	settings.buildType = selectBuildType(buildType);

	if (optResult.helpWanted) needsHelp = true;

	if (settings.configNames.canFind("all")) {
		// Select all configs
		settings.configNames = configs.map!(c => c.name).array;
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
	string compiler;

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

	Flags flags = selectFlags(gs, params);
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

	string[] args;
	args ~= params.compiler;
	args ~= imports;
	args ~= flagsStrings;
	args ~= text("-of=", artifacts[0]);
	args ~= mainFile;

	Job job = {
		params : params,
		args : args,
		artifacts : artifacts,
		extraArtifacts : extraArtifacts,
		printOutput : gs.printCallees };
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
	string[] args;
	args ~= compileRes.job.artifacts[0];
	string workDir = compileRes.job.params.artifactDir;
	Job job = { args : args, workDir : workDir, printOutput : true };
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
		if (gs.prettyPrint)
			stderr.writefln("> %-(%s\n| %)", job.args);
		else
			stderr.writefln("> %-(%s %)", job.args);
	}

	if (gs.printCommands) printCommand;

	if (gs.dryRun) return JobResult(job, 0);

	import std.process : execute, Config;
	auto result = execute(job.args, null, Config.none, size_t.max, job.workDir);

	void printCalleeOutput() {
		stderr.writeln(result.output.lineSplitter.filter!(l => !l.empty).joiner("\n"));
	}

	if (result.status == 0) {
		if (job.printOutput) printCalleeOutput;
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

string makeArchiveName(in CompileParams params) {
	static const archName = "x64";
	string buildType = params.makeBuildTypeSuffix;
	return format("%s-%s-%s-%s", params.archiveName, osName, archName, buildType);
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

	if (g.verboseCallees) flags |= Flags.f_verbose;
	if (g.betterc) flags |= Flags.f_better_c;

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
			case f_verbose: flags ~= "-v"; break;
			case f_warn_error: flags ~= "-w"; break;
			case f_warn_info: flags ~= "-wi"; break;
			case f_msg_columns: flags ~= "-vcolumns"; break;
			case f_msg_context:
				if (compiler == "dmd")
					flags ~= "-verrors=context";
				else
					flags ~= "-verrors-context";
				break;
			case f_better_c: flags ~= "-betterC"; break;
			case f_static_lib: flags ~= "-lib"; break;
			case f_dynamic_lib:
				flags ~= "-shared";
				if (compiler == "ldc2") {
					flags ~= "-fvisibility=hidden";
					if ((bits & Flags.f_better_c) == 0) {
						flags ~= "-link-defaultlib-shared=false";
					}
				}
				break;
			case f_release: flags ~= "-release"; break;
			case f_debug:
				if (compiler == "dmd")
					flags ~= "-debug";
				else
					flags ~= "-d-debug";
				break;
			case f_debug_info: flags ~= "-g"; break;
			case f_msg_gnu: flags ~= "-verror-style=gnu"; break;
			case f_checkaction_halt: flags ~= "-checkaction=halt"; break;
			case f_m64: flags ~= "-m64"; break;
			case f_link_internally:
				version(Windows) if (compiler == "ldc2") flags ~= "-link-internally";
				break;
			case f_opt:
				if (compiler == "dmd")
					flags ~= "-O";
				else {
					flags ~= ["-O3", "-mcpu=x86-64-v3", "-boundscheck=off", "-enable-inlining", "-flto=full", "-linkonce-templates"];
					if ((bits & Flags.f_better_c) == 0) {
						flags ~= "-defaultlib=phobos2-ldc-lto,druntime-ldc-lto";
					}
				}
				break;
			case f_link_debug_full:
				version(Windows) flags ~= "-L/DEBUG:FULL";
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
	run,
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
