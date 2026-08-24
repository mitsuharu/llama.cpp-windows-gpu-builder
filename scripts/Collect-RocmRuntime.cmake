if(NOT DEFINED BACKEND_DLL OR NOT EXISTS "${BACKEND_DLL}")
  message(FATAL_ERROR "BACKEND_DLL does not exist: ${BACKEND_DLL}")
endif()
if(NOT DEFINED ROCM_ROOT OR NOT IS_DIRECTORY "${ROCM_ROOT}")
  message(FATAL_ERROR "ROCM_ROOT is not a directory: ${ROCM_ROOT}")
endif()
if(NOT DEFINED DESTINATION)
  message(FATAL_ERROR "DESTINATION is required")
endif()

set(_rocm_search_dirs
  "${ROCM_ROOT}/bin"
  "${ROCM_ROOT}/lib"
  "${ROCM_ROOT}/lib/llvm/bin")

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
  string(FIND "${_normalized_dependency}" "${_normalized_root}/" _inside_rocm)
  if(_inside_rocm EQUAL 0)
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
  list(SORT _unresolved)
  message(STATUS "Unresolved system or delay-loaded dependencies: ${_unresolved}")
endif()
