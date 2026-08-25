if(NOT DEFINED BACKEND_DLL OR NOT EXISTS "${BACKEND_DLL}")
  message(FATAL_ERROR "BACKEND_DLL does not exist: ${BACKEND_DLL}")
endif()
if(NOT DEFINED ROCM_ROOT OR NOT IS_DIRECTORY "${ROCM_ROOT}")
  message(FATAL_ERROR "ROCM_ROOT is not a directory: ${ROCM_ROOT}")
endif()
if(NOT DEFINED RUNTIME_ROOT)
  set(RUNTIME_ROOT "${ROCM_ROOT}")
elseif(NOT IS_DIRECTORY "${RUNTIME_ROOT}")
  message(FATAL_ERROR "RUNTIME_ROOT is not a directory: ${RUNTIME_ROOT}")
endif()
if(NOT DEFINED DESTINATION)
  message(FATAL_ERROR "DESTINATION is required")
endif()

set(_rocm_search_dirs
  "${ROCM_ROOT}/bin"
  "${ROCM_ROOT}/lib"
  "${ROCM_ROOT}/lib/llvm/bin")
file(GLOB_RECURSE _runtime_dlls LIST_DIRECTORIES false "${RUNTIME_ROOT}/*.dll")
foreach(_runtime_dll IN LISTS _runtime_dlls)
  get_filename_component(_runtime_dir "${_runtime_dll}" DIRECTORY)
  list(APPEND _rocm_search_dirs "${_runtime_dir}")
endforeach()
list(REMOVE_DUPLICATES _rocm_search_dirs)

file(GET_RUNTIME_DEPENDENCIES
  LIBRARIES "${BACKEND_DLL}"
  DIRECTORIES ${_rocm_search_dirs}
  RESOLVED_DEPENDENCIES_VAR _resolved
  UNRESOLVED_DEPENDENCIES_VAR _unresolved
  POST_EXCLUDE_REGEXES
    "[Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\][Ss][Yy][Ss][Tt][Ee][Mm]32"
    "api-ms-win-.*"
    "ext-ms-.*")

set(_copied)
foreach(_dependency IN LISTS _resolved)
  file(TO_CMAKE_PATH "${_dependency}" _normalized_dependency)
  file(TO_CMAKE_PATH "${ROCM_ROOT}" _normalized_root)
  file(TO_CMAKE_PATH "${RUNTIME_ROOT}" _normalized_runtime_root)
  string(FIND "${_normalized_dependency}" "${_normalized_root}/" _inside_rocm)
  string(FIND "${_normalized_dependency}" "${_normalized_runtime_root}/" _inside_runtime)
  if(_inside_rocm EQUAL 0 OR _inside_runtime EQUAL 0)
    file(COPY "${_dependency}" DESTINATION "${DESTINATION}")
    get_filename_component(_dependency_name "${_dependency}" NAME)
    list(APPEND _copied "${_dependency_name}")
  endif()
endforeach()

# amd_comgr is delay-loaded by HIP on Windows and may not appear in the PE
# dependency table inspected above.
file(GLOB _comgr_dlls
  "${ROCM_ROOT}/bin/amd_comgr*.dll"
  "${ROCM_ROOT}/lib/amd_comgr*.dll")
file(GLOB_RECURSE _runtime_comgr_dlls LIST_DIRECTORIES false
  "${RUNTIME_ROOT}/amd_comgr*.dll")
list(APPEND _comgr_dlls ${_runtime_comgr_dlls})
list(REMOVE_DUPLICATES _comgr_dlls)
if(NOT _comgr_dlls)
  message(FATAL_ERROR "No amd_comgr runtime DLL was found below ${ROCM_ROOT}")
endif()
file(COPY ${_comgr_dlls} DESTINATION "${DESTINATION}")
foreach(_comgr_dll IN LISTS _comgr_dlls)
  get_filename_component(_comgr_name "${_comgr_dll}" NAME)
  list(APPEND _copied "${_comgr_name}")
endforeach()

list(REMOVE_DUPLICATES _copied)
list(SORT _copied)
string(REPLACE ";" "\n" _manifest "${_copied}")
file(WRITE "${DESTINATION}/ROCM-RUNTIME-FILES.txt" "${_manifest}\n")

if(_unresolved)
  list(FILTER _unresolved EXCLUDE REGEX "^(api|ext)-ms-win-")
endif()
if(_unresolved)
  list(SORT _unresolved)
  message(WARNING "Unresolved non-API-set or delay-loaded dependencies: ${_unresolved}")
endif()
