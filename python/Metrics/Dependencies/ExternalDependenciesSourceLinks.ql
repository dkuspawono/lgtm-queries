// Copyright 2018 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * @name External dependency source links
 * @kind source-link
 * @metricType externalDependency
 * @id py/dependency-source-links
 */

import python
import semmle.python.dependencies.TechInventory

/*
 * This query creates the source links for the ExternalDependencies.ql query.
 * Although the entities in question are of the form '/file/path<|>dependency', the
 * /file/path is a bare string relative to the root of the source archive, and not
 * tied to a particular revision. We need the File entity (the second column here) to
 * recover that information once we are in the dashboard database, using the
 * ExternalEntity.getASourceLink() method.
 */
from File sourceFile, string entity
where
  exists(PackageObject package, AstNode src |
      dependency(src, package) and
      src.getLocation().getFile() = sourceFile and
      entity = munge(sourceFile, package)
  )
select entity, sourceFile
