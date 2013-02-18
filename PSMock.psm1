<#
    PSMock - copyright(c) 2013 - Jon Wagner
    See https://github.com/jonwagner/PSMock for licensing and other information.
    Version: $version$
    Changeset: $changeset$
#>

# set up the outermost mock context
$mockContext = @{ Mocks = @{} }

<#
.Synopsis
    Returns a string containing a function that enables the Mock function.

.Description
    Returns a string containing a function that enables the Mock function.
    The string should be piped to Invoke-Expression to create the Mock function.
    The Mock function automatically looks up a command name and calls Add-Mock.

    Enable-Mock only needs to be called once per script.

.Example
    Enable-Mock | iex
    Mock MyFunction { "mocked" }

    This enables mocking, then mocks MyFunction

.Link
    Add-Mock
#>
function Enable-Mock {
@'
    <#
        .FORWARDHELPTARGETNAME Add-Mock
    #>
    function global:Mock {
        param (
            [Parameter(Mandatory=$true)] [string] $CommandName,
            [scriptblock] $With = {},
            [scriptblock] $When = {$true},
            [string] $Name,
            [switch] $OutputMock,
            [switch] $OutputCase
        )

        $PSBoundParameters.Remove('CommandName') | Out-Null

        # look up the original method for you
        $original = Microsoft.PowerShell.Management\Get-Item function:$CommandName -ErrorAction SilentlyContinue
        if (!$original) {
            $original =  Microsoft.PowerShell.Core\Get-Command -Name $CommandName -ErrorAction SilentlyContinue
        }

        Add-Mock -CommandName $CommandName -Original $original @PSBoundParameters
    }
'@
}

<#
.Synopsis
    Adds a new mock.
    Alias: Mock

.Description
    Adds a new mock. When the command is executed, the mock's With block will be called instead of the 
    specified command. This allows you to override the implementation of existing functions and commandlets.

    Generally you should call Enable-Mock|iex and then use the created Mock function to create mocks.
    
.Parameter CommandName
    The name of the command to mock.

.Parameter Original
    The original function to mock. This is required in order to automatically map the parameters for the With and When
    clauses.

.Parameter With
    The script block to execute when the mock is called.
    The script block will have the same parameters as the command it is mocking.
    If not specified, With is an empty script block and does nothing.

.Parameter When
    An optional script block that determines when the mock should be executed.
    The script block will have the same parameters as the command it is mocking.
    It should return $true if the With block should be called, $false to allow another mock to execute.
    If not specified, When returns $true and applied to all argument sets.

.Parameter Name
    An optional name that can be applied to this mock case so that the case can be identified later.
    See Get-Mock.

.Parameter OutputMock
    When specified, the mock is output.

.Parameter OutputCase
    When specified, the mock case is output.
    
.Notes
    If there are no mocks applicable to the current call, the original function is executed.
    You can prevent the original function from executing by adding an empty mock.

    When mocking a function that does not exist, Add-Mock does not know the parameters
    for the With and When script blocks. In this case, you must manually add the param clause
    or access $args directly.

    If more than one mock is added for a command, each addition is called a Mock Case.
    Each case is tracked separately. The call counts and arguments are separate, and
    each case can be removed separately. To give a case a name, use the -Name parameter
    when creating the case.

.Example
    Enable-Mock | iex
    Mock Get-ChildItem { "no soup for you" }

    This example overrides the Get-ChildItem commandlet to return "no soup for you" in all cases.

.Example
    Enable-Mock | iex
    Mock Get-ChildItem { "no $Path for you" } -when { $Path -eq 'soup' }

    This example overrides the Get-ChildItem commandlet to return "no soup for you" when you ask for soup.
    Note that the $Path parameters are available from within the script blocks.

.Example
    Enable-Mock | iex
    Mock Get-ChildItem { "no $Path for you" } -when { $Path -eq 'soup' } -name Soup

    This example overrides the Get-ChildItem commandlet with two separate cases.

.Link
    Get-Mock
.Link
    MockContext
.Link
    Remove-Mock
#>
function Add-Mock {
    param (
        [string] $CommandName,
        [object] $Original,
        [scriptblock] $With = {},
        [scriptblock] $When = {$true},
        [string] $Name,
        [switch] $OutputMock,
        [switch] $OutputCase
    )

    # default the name if it is not given
    if (!$Name) {
        $Name = $When.ToString()
        if ($Name -eq '$true') {
            $Name = 'default'
        }
    }

    # build a new mock case
    $case = @{
        "Name" = $Name
        "When" = $When
        "With" = $With
        "Calls" = @()
        "Count" = 0
        "IsDefault" = ($When.ToString() -eq '$true')
    }

    # see if there is an existing mock at the current level
    $mock = $mockContext.Mocks[$CommandName]

    # if there is already a mock, add this case to the list of cases
    if ($mock) {

        # add the new case to the list.
        if ($case.IsDefault) {
            # default cases go last in the list, but before any older cases
            $cases = @($mock.Cases |? { !$_.IsDefault })
            $cases += $case
            $cases += @($mock.Cases |? { $_.IsDefault })
            $mock.Cases = $cases
        }
        else {
            # new non-default cases go in the front of the list
            $mock.Cases = ,$case + $mock.Cases
        }

        if ($mock.Parameters) {
            # we also have to inject the parameters into when and with so the developer doesn't need to
            $case.When = "{ $($mock.CmdletBinding) param ($($mock.Parameters)) $($case.When) }" | iex
            $case.With = "{ $($mock.CmdletBinding) param ($($mock.Parameters)) $($case.With) }" | iex
        }
        
        if ($OutputMock) { $mock }
        if ($OutputCase) { $case }
        return
    }

    # no mock yet, need to wire up the mock function
    # create the mock
    $mock = @{
        "Cases" = @($case)
        "Calls" = @()
        "Count" = 0
        "BaseMock" = (Get-Mock $CommandName)
        "Original" = $Original
    }

    # you can't mock an alias, because we use aliases to mock
    if ($Original.CommandType -eq 'Alias') {
        throw "PSMock cannot mock alias $CommandName. Mock the target instead."
        return
    }

    # if there isn't a base mock, then we need to initialize the mock
    if (!$mock.BaseMock) {

        # if there was an original command, figure out its parameters
        if ($mock.Original) {

            # get the parameters from the original command
            $metadata=Microsoft.PowerShell.Utility\New-Object System.Management.Automation.CommandMetaData $mock.Original
            @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'ErrorVariable', 'WarningVariable', 'OutVariable', 'OutBuffer') |
                % { $metaData.Parameters.Remove($_) | Out-Null }
            $mock.CmdletBinding = [Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($metadata)
            $mock.Parameters = [Management.Automation.ProxyCommand]::GetParamBlock($metadata)

            # we also have to inject the parameters into when and with so the developer doesn't need to
            $case.When = "{ $($mock.CmdletBinding) param ($($mock.Parameters)) $($case.When) }" | iex
            $case.With = "{ $($mock.CmdletBinding) param ($($mock.Parameters)) $($case.With) }" | iex
        }

        # we need to modify execution in the scope that called this module.
        # it may not be the global scope, so
        # create a global alias to the new mock function. aliases work in any scope.
        Microsoft.PowerShell.Utility\Set-Alias $CommandName PSMock-$CommandName -Scope Global

        # create a global function to implement the mock
        Microsoft.PowerShell.Management\Set-Item function:\global:PSMock-$CommandName -value `
            "$($mock.CmdletBinding) param ($($mock.Parameters)) Invoke-Mock @{ CommandName=`"$CommandName`"; BoundParameters=`$PSBoundParameters; Args=`$args }"
    }

    # this mock is now official
    $mockContext.Mocks[$CommandName] = $mock

    if ($OutputMock) { $mock }
    if ($OutputCase) { $case }
    return
}

<#
.Synopsis
    Gets the mock associated with a command.

.Description
    Gets the mock associated with a command. Returns nothing if there are no mocks.

.Parameter CommandName
    The name of the command to look up.

.Notes
    If there are nested mock contexts, then returns the most relevant mock.
    In a nested mock context, to get a base mock, use $mock.BaseMock.
    See MockContext.

    If more than one mock is added for a command, each addition is called a Mock Case.
    Each case is tracked separately. The call counts and arguments are separate, and
    each case can be removed separately. To give a case a name, use the -Name parameter
    when creating the case.

.Example
    Get-Mock MyFunction

    This example gets the mock for MyFunction.

Name                           Value                                                  
----                           -----                                                  
Cases                          {System.Collections.Hashtable}                         
Count                          0                                                      
Calls                          {}  

.Example
    $case = Get-Mock MyFunction -Name "specialcase"

    This example gets the specialcase case for MyFunction

.Link
    Add-Mock
.Link
    MockContext
.Link
    Remove-Mock
#>
function Get-Mock {
    param (
        [Parameter(Mandatory=$true)] [string] $CommandName,
        [string] $Case
    )

    # go through the stack of contexts
    $context = $mockContext
    while ($context) {

        # if there is a mock, return it
        $mock = $context.Mocks[$CommandName]
        if ($mock) {

            if ($Case) {
                return $($mock.Cases |? Name -eq $Case)
            }
            else {
                return $mock
            }
        }

        # keep looking
        $context = $context.Inner
    }
}

<#
.Synopsis
    Removes the mocks associated with a command.

.Description
    Removes the mocks associated with a command for the current mock context.
    If multiple mock cases are defined on for the command, all of them are removed unless the Name parameter is specified.

.Parameter CommandName
    The name of the command to remove mocks.

.Parameter Name
    The name of the mock case to remove. If not specified, then all cases are removed.

.Notes
    If there are nested mock contexts, Remove-Mock will only remove the mocks defined in the current context.
    If there are mocks defined in other contexts, those mocks will still apply.
    See MockContext.

.Example
    Remove-Mock MyFunction

    This example removes the mock associated with MyFunction

.Link
    Add-Mock
.Link
    Get-Mock
.Link
    MockContext
#>
function Remove-Mock {
    param (
        [Parameter(Mandatory=$true)] [string] $CommandName,
        [string] $Name
    )

    # find the mock
    $mock = $mockContext.Mocks[$CommandName]
    if (!$mock) {
        Write-Error "There is no mock for $CommandName"
        return
    }

    # if a name was specified, remove that case
    if ($Name) {
        # remove the case
        $mock.Cases = @($mock.Cases |? Name -ne $Name)

        # if there are cases left, we can quit, otherwise continue and remove the mock
        if ($mock.Cases.Count -gt 0) {
            return
        }
    }

    # remove the mock from the table
    $mockContext.Mocks.Remove($CommandName)

    # if there is no base mock to fall back on
    if (!$mock.BaseMock) {
        # remove the function and the alias
        Microsoft.PowerShell.Management\Remove-Item function:\global:PSMock-$CommandName -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item function:PSMock-$CommandName -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item alias:$CommandName
    }
}

<#
.Synopsis
    Removes all mocks in the current mock context.

.Description
    Removes all mocks in the current mock context.

.Notes
    If there are nested mock contexts, Remove-Mock will only remove the mocks defined in the current context.
    If there are mocks defined in other contexts, those mocks will still apply.
    See MockContext.

.Example
    Remove-Mock MyFunction

    This example removes the mock associated with MyFunction

.Link
    Add-Mock
.Link
    MockContext
#>
function Clear-Mocks {

    @($mockContext.Mocks.Keys) |% { Remove-Mock $_ }
}

<#
.Synopsis
    Enters a new mock context that can be removed separately.

.Description
    Enters a new mock context that can be removed separately.
    New mocks that are created take precedence over existing mocks.

.Example
    Enter-MockContext

    This example begins a new mock context.

.Link
    Exit-MockContext
.Link
    MockContext
#>
function Enter-MockContext {

    $script:mockContext = @{
        Mocks = @{}
        Inner = $mockContext
    }
}

<#
.Synopsis
    Exits the current mock context and clears all of the mocks defined in the context.

.Description
    Exits the current mock context and clears all of the mocks defined in the context.

.Example
    Exit-MockContext

    This example ends the current mock context.

.Link
    Enter-MockContext
.Link
    MockContext
#>
function Exit-MockContext {

    Clear-Mocks

    if ($mockContext.Inner) {
        $script:mockContext = $mockContext.Inner
    }
}

<#
.Synopsis
    Executes a script block from within a new mock context.

.Description
    Executes a script block from within a new mock context.
    Any mocks created within the context are automatically removed when the context is exited.

    Mock contexts can be nested, and the mocks are unwound appropriately.

.Example
    MockContext { 
        Mock MyFunction
    }
    # The mock for MyFunction is removed.

.Link
    Enter-MockContext
#>
function MockContext {
    param (
        [scriptblock] $Script
    )

    try {
        Enter-MockContext

        & $Script
    }
    finally {
        Exit-MockContext
    }
}

<#
.Synopsis
    Resolves and invokes a mock by name.
    This is not intended to be called by your code.

.Description
    Resolves the proper invocation of a mock by name and parameters.
    If the mock does not exist, then nothing happens.

.Parameter Call
    The function call to invoke. This should be a hashtable of CommandName, Args, and BoundParameters.

.Example
    Invoke-Mock @{ 'CommandName'='Get-ChildItem' 'BoundParameters' = @{ 'Path'="z:\" } }

    Invokes the mock installed for Get-ChildItem.
#>
function Invoke-Mock {
    param (
        [HashTable] $Call
    )

    # find the mock, there has to be one
    $mock = Get-Mock $Call.CommandName
    if (!$mock) {
        throw "No mock is defined for $($Call.CommandName)"
    }

    $args = $Call.Args
    $boundParameters = $Call.BoundParameters

    while ($mock) {

        # go through all of the cases and find the first match
        for ($i = 0; $i -lt $mock.Cases.Length; $i++) {

            $case = $mock.Cases[$i]

            # check out the when clause to see if its a match
            if (& $case.When @args @BoundParameters) {

                # keep track of the number of times called
                $case.Count++;
                $case.Calls += $call
                $mock.Count++;
                $mock.Calls += $call

                # call the replacement
                & $case.With @args @BoundParameters
                return
            }
        }

        # if there was an original method to call, call it
        if ($mock.Original) {
            # no case matches, so fall through to the base
            & $mock.Original @args @BoundParameters

            return
        }

        # try the base mock
        $mock = $mock.BaseMock
    }
}

# Cleans up outstanding mocks if the module is unloaded.
# This keeps the system from getting really crazy if you force-load the module.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # this gets called when we are unloading the mock library
    # exit all outstanding mock contexts
    while ($mockContext.Inner) {
        Exit-MockContext
    }

    # clear the root mock context
    Clear-Mocks
}

Export-ModuleMember Enable-Mock, Add-Mock, Remove-Mock, Clear-Mocks, Get-Mock, Invoke-Mock, Enter-MockContext, Exit-MockContext, MockContext