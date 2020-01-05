import { HierarchyPointNode } from 'd3'
import * as d3 from 'd3'
import Node, { WhichTree } from './Node'
import * as TreeHelper from './TreeHelper'
import { State, MyMap, Core, TreeContainer } from '../components/vis/TreeContainer'
import { cloneDeep, last, min, max } from 'lodash'
import { Collapse } from 'react-select/lib/animated/transitions'
import { headers } from './Helper'
import { MergedTreeContainer } from '../components/vis/MergedTreeContainer'

export const nextSol = (instance: TreeContainer) => {
	instance.setState((prevState: State) => {
		const solId = TreeHelper.getNextSolId(prevState)

		if (solId === -1) {
			return null
		}

		const newMap = TreeHelper.showAllAncestors(prevState, solId)
		return { selected: solId, id2Node: newMap }
	})
}
export const nextFailed = (instance: TreeContainer) => {
	if (!instance.state.solveable) {
		goLeft(instance)
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
		let nextId = TreeHelper.getNextFailedId(instance.state.selected, instance.props.core.solAncestorIds)
		if (nextId !== -1) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(prevState, nextId)
				return { selected: nextId, id2Node: newMap }
			})
		}
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected + 1)) {
		let nextId = TreeHelper.getNextFailedId(instance.state.selected + 1, instance.props.core.solAncestorIds)
		if (nextId !== -1) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(prevState, nextId)
				return { selected: nextId, id2Node: newMap }
			})
		}
	} else {
		goLeft(instance)
	}
}

export const prevFailed = (instance: TreeContainer) => {
	if (!instance.state.solveable) {
		goToPreviousHandler(instance)
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
		let nextId = TreeHelper.getPrevFailedId(instance.state.selected, instance.props.core.solAncestorIds)

		if (nextId in instance.state.id2Node) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(prevState, nextId)
				return { selected: nextId, id2Node: newMap }
			})
		} else {
			goPrev(instance, nextId + 1)
		}
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected - 1)) {
		let nextId = TreeHelper.getPrevFailedId(instance.state.selected - 1, instance.props.core.solAncestorIds)

		if (nextId === -1) {
			return
		}

		if (nextId in instance.state.id2Node) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(prevState, nextId)
				return { selected: nextId, id2Node: newMap }
			})
		} else {
			goPrev(instance, nextId + 1)
		}
	} else {
		goPrev(instance)
	}
}

export const prevSol = (instance: TreeContainer) => {
	instance.setState((prevState: State) => {
		const solId = TreeHelper.getPrevSolId(prevState)

		if (solId === -1) {
			return null
		}

		const newMap = TreeHelper.showAllAncestors(prevState, solId)
		return { selected: solId, id2Node: newMap }
	})
}
export const goRightBoyo = (map: MyMap, currentSelected: number) => {
	const current = map[currentSelected]
	if (!current.children) {
		return { selected: currentSelected }
	}
	if (current.children.length < 2) {
		return { selected: currentSelected }
	}
	return { selected: current.children[1].id }
}

export const goRight = (instance: TreeContainer) => {
	instance.setState((prev: State) => {
		return goRightBoyo(prev.id2Node, prev.selected)

		// const current = prev.id2Node[prev.selected]
		// if (!current.children) {
		//   return null
		// }
		// if (current.children.length < 2) {
		//   return null
		// }
		// return { selected: current.children[1].id }
	})
}

export const goUp = (instance: TreeContainer) => {
	instance.setState((prev: State) => {
		const current = prev.id2Node[prev.selected]
		if (current.parentId === -1) {
			return null
		}
		return { selected: current.parentId }
	})
}

export const fetchDescendants = async (
	selected: number,
	map: MyMap,
	path: string,
	loadDepth: number,
	nimServerPort: number,
	treeId: WhichTree,
) => {
	const payload = {
		path: path,
		nodeId: selected,
		depth: loadDepth,
	}
	map = await fetch(`http://localhost:${nimServerPort}/loadNodes`, {
		method: 'post',
		headers: headers,
		body: JSON.stringify(payload),
	})
		.then((data) => data.json())
		.then((nodes) => TreeHelper.insertNodesBoyo(nodes, map, treeId))

	return map
}

export const goLeftBoyo = async (
	selected: number,
	map: MyMap,
	playing: boolean,
	collapseAsExploring: boolean,
	path: string,
	loadDepth: number,
	nimServerPort: number,
	treeId: WhichTree,
) => {
	const nextId = selected + 1

	const parent = map[nextId]

	const grandParent = parent ? map[parent.parentId] : undefined

	if (nextId in map) {
		const newMap = TreeHelper.showAllAncestorsBoyo(map, selected)

		if (
			playing &&
			collapseAsExploring &&
			grandParent &&
			grandParent.children &&
			nextId !== grandParent.children![0].id
		) {
			Node.collapseNode(newMap[grandParent.children![0].id])
		}

		// console.log("prevId", selected)
		// console.log("nextId", nextId)

		return { id2Node: map, selected: nextId }
	}

	const payload = {
		path: path,
		nodeId: selected,
		depth: loadDepth,
	}

	map = await fetch(`http://localhost:${nimServerPort}/loadNodes`, {
		method: 'post',
		headers: headers,
		body: JSON.stringify(payload),
	})
		.then((data) => data.json())
		.then((nodes) => TreeHelper.insertNodesBoyo(nodes, map, treeId))

	return { id2Node: map, selected: selected }
}

export const goLeft = async (instance: TreeContainer) => {
	const nextId = instance.state.selected + 1

	const parent = instance.state.id2Node[nextId]

	const grandParent = parent ? instance.state.id2Node[parent.parentId] : undefined

	if (nextId in instance.state.id2Node) {
		instance.setState((prevState: State) => {
			const newMap = TreeHelper.showAllAncestors(prevState, instance.state.selected)

			if (
				instance.props.playing &&
				instance.props.collapseAsExploring &&
				grandParent &&
				grandParent.children &&
				nextId !== grandParent.children![0].id
			) {
				Node.collapseNode(newMap[grandParent.children![0].id])
			}

			return { selected: nextId, id2Node: newMap }
		})
		return
	}

	const payload = {
		path: instance.props.path,
		nodeId: instance.state.selected,
		depth: instance.props.loadDepth,
	}

	await fetch(`http://localhost:${instance.props.nimServerPort}/loadNodes`, {
		method: 'post',
		headers: headers,
		body: JSON.stringify(payload),
	})
		.then((data) => data.json())
		.then((nodes) => TreeHelper.insertNodes(nodes, instance.state.selected, instance))
}

export const goPrev = (instance: TreeContainer, start?: number) => {
	let current = start ? start : instance.state.selected

	if (current === 0) {
		return
	}

	const nextId = current - 1

	if (nextId in instance.state.id2Node) {
		instance.setState((prevState: State) => {
			const newMap = TreeHelper.showAllAncestors(prevState, nextId)
			return { selected: nextId, id2Node: newMap }
		})
		return
	}

	loadAncestors(instance.props.path, nextId, instance)
}
export const fetchAncestors = async (path: string, nodeId: number, nimServerPort: number): Promise<Node[]> => {
	const payload = {
		path: path,
		nodeId: nodeId,
	}

	const res = await fetch(`http://localhost:${nimServerPort}/loadAncestors`, {
		method: 'post',
		headers: headers,
		body: JSON.stringify(payload),
	})

	const json = await res.json()

	// console.log(JSON.stringify(json))
	return json
}

export const loadAncestors = async (path: string, nodeId: number, instance: TreeContainer) => {
	const nodes = await fetchAncestors(path, nodeId, instance.props.nimServerPort)
	TreeHelper.insertNodes(nodes, nodeId, instance)
}

export const nextSolBranch = (instance: TreeContainer) => {
	if (!instance.state.solveable) {
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
		const currentIndex = instance.props.core.solAncestorIds.indexOf(instance.state.selected)
		if (currentIndex + 1 < instance.props.core.solAncestorIds.length) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(
					prevState,
					instance.props.core.solAncestorIds[currentIndex + 1],
				)
				return {
					selected: instance.props.core.solAncestorIds[currentIndex + 1],
					id2Node: newMap,
				}
			})
		}
		return
	}

	const nextId = min(
		instance.props.core.solAncestorIds.filter((num) => {
			return instance.state.selected < num
		}),
	)

	if (!nextId) {
		return
	}

	instance.setState((prevState: State) => {
		const newMap = TreeHelper.showAllAncestors(prevState, nextId)
		return {
			selected: nextId,
			id2Node: newMap,
		}
	})
}

export const prevSolBranch = (instance: TreeContainer) => {
	if (!instance.state.solveable) {
		return
	}

	if (instance.props.core.solAncestorIds.includes(instance.state.selected)) {
		const currentIndex = instance.props.core.solAncestorIds.indexOf(instance.state.selected)
		if (currentIndex - 1 >= 0) {
			instance.setState((prevState: State) => {
				const newMap = TreeHelper.showAllAncestors(
					prevState,
					instance.props.core.solAncestorIds[currentIndex - 1],
				)
				return {
					selected: instance.props.core.solAncestorIds[currentIndex - 1],
					id2Node: newMap,
				}
			})
		}
		return
	}

	const nextId = max(
		instance.props.core.solAncestorIds.filter((num) => {
			return instance.state.selected > num
		}),
	)

	if (!nextId) {
		return
	}

	instance.setState((prevState: State) => {
		const newMap = TreeHelper.showAllAncestors(prevState, nextId)
		return {
			selected: nextId,
			id2Node: newMap,
		}
	})
}

export const goToPreviousHandler = (instance: TreeContainer) => {
	goPrev(instance)
	if (instance.props.collapseAsExploring && instance.props.playing) {
		instance.collapse()
	}
}

// TODO need to write comprehensive tests for the visualisation before any modifications to this file.
