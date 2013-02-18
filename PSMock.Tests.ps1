# re-import the module
Import-Module .\PSMock.psm1 -Force
Enable-Mock | iex

#########################################################
# our heros
#########################################################

function Original {
    param ([string] $p)

    "original, $p"
}

function Caller() {
    param ([string] $p)

    Original $p
}

#########################################################
# basic testing
#########################################################
$failedTests = 0
function Assert-Equal {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)] $case,
        [Parameter(Position=1)] $expected,
        [Parameter(Position=2)] $actual
    )

    if ($expected -ne $actual) {
        Write-Host  "FAIL: $case Expected: $expected, Got: $actual" -ForegroundColor Yellow
        $script:failedTests++
    }
    else {
        Write-Host "PASS: $case"
    }
}

#########################################################
# function mocks and general testing
#########################################################

Assert-Equal "NO MOCKS" "original, test" (Caller 'test')

Mock Original { "case mock, $p" } -when { $p -eq "test" }
Assert-Equal "ONE CASE MOCK" "case mock, test" (Caller 'test')
Assert-Equal "ONE CASE MOCK - DIRECT CALL" "case mock, test" (Original 'test')

Mock Original { "default mock, $p" }
Assert-Equal "TWO CASE MOCK OVERRIDE" "case mock, test" (Caller 'test')
Assert-Equal "TWO CASE MOCK FALLBACK" "default mock, other" (Caller 'other')

Remove-Mock Original
Assert-Equal "REMOVED MOCKS" "original, test" (Caller 'test')

Mock Original { "case mock, $p" } -when { $p -eq "test" }
Assert-Equal "RE-ADD MOCK" "case mock, test" (Caller 'test')

Clear-Mocks
Assert-Equal "CLEAR MOCKS" "original, test" (Caller 'test')

Mock Original { "default mock, $p" }
Mock Original { "case mock, $p" } -when { $p -eq "test" }
Assert-Equal "DEFAULT ORDER OVERRIDE" "case mock, test" (Caller 'test')
Assert-Equal "DEFAULT ORDER FALLBACK" "default mock, other" (Caller 'other')
Clear-Mocks

$who = 'test'
MockContext {

    Mock Original { "case mock, $p" } -when { $p -eq "test" }
    Assert-Equal "MOCK IN CONTEXT" "case mock, test" (Caller $who)

    MockContext {
        Assert-Equal "MOCK IN NESTED CONTEXT" "case mock, test" (Caller $who)

        Mock Original { "nested mock, $p" } -when { $p -eq "test" }
        Assert-Equal "OVERRIDE IN NESTED CONTEXT" "nested mock, test" (Caller $who)

        Assert-Equal "FALLBACK IN NESTED CONTEXT" "original, other" (Caller 'other')
    }

    Assert-Equal "MOCK OUT OF NESTED CONTEXT" "case mock, test" (Caller $who)
}
Assert-Equal "MOCK OUT OF CONTEXT" "original, test" (Caller $who)

try {
    MockContext {

        Mock Original { "case mock, $p" } -when { $p -eq "test" }
        Assert-Equal "MOCK IN CONTEXT" "case mock, test" (Caller $who)
        throw "quit"
    }
}
catch {}
Assert-Equal "MOCK CONTEXT THROWS AND CLEANS UP" "original, test" (Caller $who)

MockContext {
    Mock Original { "mocked" }
    MockContext {
        Remove-Mock Original -ErrorVariable mockerror -ErrorAction SilentlyContinue
        Assert-Equal "REMOVE MOCK did throw" $true ($mockerror -ne $null)
    }
}

Clear-Mocks
Mock Original { "case mock, $p" } -when { $p -eq "test" } -name test
Mock Original { "default mock, $p" }
Assert-Equal "REMOVE NAMED - BEFORE" "case mock, test" (Caller 'test')
Remove-Mock Original -Name test
Assert-Equal "REMOVE NAMED - AFTER" "default mock, test" (Caller 'test')

Clear-Mocks
Mock Original { "default mock 1, $p" } -name one
Mock Original { "default mock 2, $p" } -name two
Assert-Equal "MULTIPLE DEFAULTS" "default mock 2, test" (Caller 'test')

#########################################################
# mocking a function that doesn't exist
#########################################################
Clear-Mocks

Mock NoFunction { "nothing" }
Assert-Equal "MOCK NON-FUNCTION" "nothing" (NoFunction)
Remove-Mock NoFunction
Assert-Equal "NON-FUNCTION REMOVED" -Expected $null (Get-Item function:NoFunction -ErrorAction SilentlyContinue)
Mock NoFunction { param ([string] $p) "nothing, $p" }
Assert-Equal "MOCK NON-FUNCTION WITH PARAM" "nothing, you" (NoFunction "you")
Remove-Mock NoFunction

Mock NoFunction { "nothing" }
Mock NoFunction { "override" }
Assert-Equal "MOCK NON-FUNCTION OVERRIDE" "override" (NoFunction)

#########################################################
# mocking a command
#########################################################
Clear-Mocks

MockContext {

    Mock Get-ChildItem { "soup $Path" } -when { $Path -eq 'c:\' }
    Mock Get-ChildItem { "sandwich $Path" } -when { $Path -eq 'z:\' }
    Mock Get-ChildItem { "no soup" }
    Assert-Equal "COMMAND WITH PARAMETERS" "soup c:\" (Get-ChildItem -Path 'c:\')
    Assert-Equal "COMMAND WITH PARAMETERS AND OVERRIDE" "sandwich z:\" (Get-ChildItem -Path 'z:\')
    Assert-Equal "COMMAND WITH NO PARAMETERS" "no soup" (Get-ChildItem -Path 'd:\')
}

#########################################################
# mocking an alias
#########################################################
Clear-Mocks
$mockerror = $null
try {
    Mock gu {} -ErrorVariable mockerror -ErrorAction SilentlyContinue
} catch {}
Assert-Equal "MOCK ALIAS did throw" $true ($mockerror -ne $null)

#########################################################
# scope tests
#########################################################
Clear-Mocks

# execute this in a function to test non-global scope
function Test-Mocks {

    $scope = 'function'

    function FunctionOriginal {
        param ([string] $p)

        "original, $p"
    }

    function FunctionCaller {
        param ([string] $p)

        FunctionOriginal $p
    }

    MockContext {
        Assert-Equal "CALLBLOCK: NO MOCKS" "original, $scope" (FunctionCaller $scope)

        Mock FunctionOriginal { "case mock, $p" } -when { $p -eq "function" }
        Assert-Equal "CALLBLOCK: ONE CASE MOCK" "case mock, $scope" (FunctionCaller $scope)
    }
}
Test-Mocks

# execute this in a call block to test non-global scope
& {
    $scope = 'callblock'

    function CallBlockOriginal {
        param ([string] $p)

        "original, $p"
    }

    function CallBlockCaller {
        param ([string] $p)

        CallBlockOriginal $p
    }

    MockContext {
        Assert-Equal "CALLBLOCK: NO MOCKS" "original, $scope" (CallBlockCaller $scope)

        Mock CallBlockOriginal { "case mock, $p" } -when { $p -eq "callblock" }
        Assert-Equal "CALLBLOCK: ONE CASE MOCK" "case mock, $scope" (CallBlockCaller $scope)
    }
}

#########################################################
# reload the module with outstanding mocks
#########################################################

Mock Original { "mocked, $p" }
Import-Module .\PSMock.psm1 -force
Enable-Mock | iex
Assert-Equal "FORCE RELOAD - NO MOCKS" "original, test" (Caller 'test')
Mock Original { "mocked, $p" }
Assert-Equal "RELOAD - ONE MOCKS" "mocked, test" (Caller 'test')
Import-Module .\PSMock.psm1 -force
Enable-Mock | iex

#########################################################
# redefine a function with outstanding mocks
#########################################################

Assert-Equal "REDEFINE - NO MOCKS" "original, test" (Caller 'test')
Mock Original { "mocked, $p" }
Assert-Equal "REDEFINE - MOCKS" "mocked, test" (Caller 'test')
function Original { "redefined" }
Assert-Equal "REDEFINE - REDEFINED" "mocked, test" (Caller 'test')
Remove-Mock Original
Assert-Equal "REDEFINE - REMOVED" "redefined" (Caller 'test')
function Original { param ([string]$p) "original, $p" }

#########################################################
# tracking calls
#########################################################
Mock Original { "case mock, $p" } -when { $p -eq "test" }
$mock = Mock Original { "default mock, $p" } -OutputMock
Assert-Equal "COUNT - 0" 0 $mock.Count
Original 'test' | Out-Null
Original 'other' | Out-Null
Assert-Equal "COUNT - 2" 2 $mock.Count
Assert-Equal "CALLS - args" 'test' $mock.Calls[0].BoundParameters['p']
$case = Get-Mock Original -Case default
Assert-Equal "CASE CALLS - 1" 1 $case.Count

if ($failedTests -gt 0) {
    throw "$failedTests tests failed"
}

Clear-Mocks