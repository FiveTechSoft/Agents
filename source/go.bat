@setlocal
@call "%ProgramFiles%\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" amd64
c:\harbour\bin\win\msvc64\hbmk2 agents.hbp -comp=msvc64
@endlocal