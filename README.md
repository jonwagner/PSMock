# PSMock #

**PSMock** (pronounced "smock" or "puh-smock") is a mocking module for PowerShell.

PSMock can mock functions and commands, filter mocks, track calls, and manage multiple contexts from whatever program you are running. Works with dot-sourced code, scripts, and call blocks.

## Examples ##

Getting started:

	Import-Module PSMock

A simple mock:

	# Need this to automatically handle scope changes
	Enable-Mock | iex

	function Original { "original" }
	Original | Out-Host			# "original"

	Mock Original { "mocked" }
	Original | Out-Host			# "mocked"

Mocking with cases:

	Enable-Mock | iex

	function Hello { param ([string] $who) "Hello, $who" }
	Hello you		# "Hello, you"

	Mock Hello { } -when { $who -eq "Bob" }
	Hello you		# "Hello, you"
	Hello bob		# nothing

	Mock Hello { "Good day, $who" }
	Hello bob		# nothing
	Hello you		# "Good day, you"

Call tracking:

	Enable-Mock | iex

	function Hello { param ([string] $who) "Hello, $who" }
	Mock Hello { } -when { $who -eq "Bob" } -name Bob
	Mock Hello { "Good day, $who" }
	Hello bob					# nothing
	Hello you					# "Good day, you"
	(Get-Mock Hello).Count		# 2
	(Get-Mock Hello -case Bob).Count		# 1
	(Get-Mock Hello -case default).Count	# 1
	(Get-Mock Hello -case default).Calls[0].BoundParameters['who']	# "you"

## Features ##

See the [PSMock wiki](https://github.com/jonwagner/PSMock/wiki) for full documentation.

* Works standalone or with another test framework
* Mocks any function or command
* Conditional mocks with the -when parameter
* Named cases can be added/removed
* Mock contexts to automatically remove mocks
* Call tracking at the mock and case level

## Getting PSMock ##

A variety of ways:

- PSGet - [http://psget.net/](http://psget.net)
	- Get PSGet
	- Install-Module -nugetpackageid PSMock
	- PSMock will be installed into as a global module
- NuGet - [http://nuget.org/packages/PSMock](http://nuget.org/packages/PSMock)
	- Install-Package PSMock
	- PSMock will be installed into your current project
- GitHub - [Download PSMock.psm1](https://github.com/jonwagner/PSMock/tree/master/PSMock.psm1)
	- Copy the file to your modules folder or a local folder

## Credits ##

PSMock was inspired by the great work by the [Pester](https://github.com/pester/Pester) team. See [PSMock v Pester](https://github.com/jonwagner/PSMock/wiki/PSMock%20v%20Pester) on the wiki to learn about some differences.

