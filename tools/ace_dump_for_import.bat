@echo off
REM ===========================================================================
REM ace_dump_for_import.bat — ACE 레거시 DB에서 import에 필요한 테이블만 백업
REM ===========================================================================
REM Windows 오프라인 ACE PC 용. import 화면(/configuracion/importar-legacy)이
REM 읽는 9개 테이블만 plain 포맷(-Fp)으로 덤프하여 25MB 상한을 피합니다.
REM
REM 사용법:
REM   ace_dump_for_import.bat
REM   set ACE_DB=ace_db & set ACE_USER=postgres & ace_dump_for_import.bat
REM
REM 생성된 ace_import.sql 을 "Importar Legacy" 화면에 업로드하세요.
REM ===========================================================================
setlocal

if "%ACE_DB%"==""   set ACE_DB=ace_db
if "%ACE_USER%"==""  set ACE_USER=postgres
if "%ACE_HOST%"==""  set ACE_HOST=localhost
if "%ACE_PORT%"==""  set ACE_PORT=5432
set OUTPUT=ace_import.sql

echo ACE -^> import 백업 시작 (DB=%ACE_DB%, user=%ACE_USER%)

pg_dump -h %ACE_HOST% -p %ACE_PORT% -U %ACE_USER% -d %ACE_DB% -Fp --no-owner --no-privileges ^
  -t public.tipos -t public.color -t public.temporadas ^
  -t public.origenes -t public.empresas -t public.todocodigos ^
  -t public.codigos -t public.vendedores -t public.clientes ^
  -f %OUTPUT%

if errorlevel 1 (
  echo 백업 실패: pg_dump 가 오류를 반환했습니다.
  echo   비밀번호가 필요하면 set PGPASSWORD=... 후 다시 실행하세요.
  exit /b 1
)

echo.
echo 백업 완료: %OUTPUT%
echo Importar Legacy 화면에 이 파일을 업로드하세요.
endlocal
