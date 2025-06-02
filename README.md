# PowerXML

PowerXML is a set of PowerShell CmdLets that ease use of various XML tooling.

Goals:

- Provide a unified front end for various XML processors (specificially XProc processors)
- Automatically gather required dependencies to perform a task

PowerXML currently includes the Polyglot Package Manager (PPM), to support dependency management. Post MVP stage, this should become its own project.

## Requirements

- [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.5) Core 7.5+
- [Java JDK 17](https://learn.microsoft.com/en-us/java/openjdk/download)+

## Installing the module

First install the InstallModuleFromGitHub module, which will make updating PowerXML easier.

```powershell
Install-Module -Name InstallModuleFromGitHub -RequiredVersion 0.3
```

```powershell
Install-ModuleFromGitHub -GitHubRepo theturnout/PowerXML -Branch develop
```

## Transform-XML CmdLet

`PowerXML` exposes a single CmdLet, `Transform-XML`. Full documentation is available by calling `help Transform-XML`.

### Calling XProc 

Specify the pipeline using `-pipeline`. `-inPort` and `-outPort` is used if there are input ports or output ports in the XProc Pipeline (`xpl`), respectively. They use PowerShell [hashtable syntax](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_hash_tables?view=powershell-7.5)

```powershell
.\powerxml.ps1 -pipeline testixml_in.xpl -inPort @{'source'='input.txt';'grammar'='grammar.txt'}
```