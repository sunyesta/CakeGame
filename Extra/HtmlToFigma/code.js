// This code runs in the main Figma sandbox.
// It receives the JSON tree from the UI and builds the actual Figma layers.

figma.showUI(__html__, { width: 800, height: 600, themeColors: true });

async function loadFonts() {
	await figma.loadFontAsync({ family: "Inter", style: "Regular" });
	await figma.loadFontAsync({ family: "Inter", style: "Medium" });
	await figma.loadFontAsync({ family: "Inter", style: "Bold" });
}

async function createFigmaNode(data, parentNode = null) {
	if (!data) return null;

	let node;

	// 1. Create TEXT Nodes
	if (data.type === "TEXT") {
		const textNode = figma.createText();
		await loadFonts();
		textNode.characters = data.text || " ";
		textNode.fontSize = data.fontSize || 16;

		if (data.fills && data.fills.length > 0) {
			textNode.fills = data.fills;
		}

		// Check font weight
		if (data.fontWeight >= 700) {
			textNode.fontName = { family: "Inter", style: "Bold" };
		} else if (data.fontWeight >= 500) {
			textNode.fontName = { family: "Inter", style: "Medium" };
		}

		node = textNode;
	}
	// 2. Create FRAME Nodes (Divs, Buttons, etc.)
	else {
		const frameNode = figma.createFrame();
		frameNode.name = data.tagName || "Frame";

		// Safely resize
		const width = Math.max(0.01, data.width || 100);
		const height = Math.max(0.01, data.height || 100);
		frameNode.resize(width, height);

		// Apply Styles
		if (data.fills) frameNode.fills = data.fills;
		if (data.strokes && data.strokeWeight > 0) {
			frameNode.strokes = data.strokes;
			frameNode.strokeWeight = data.strokeWeight;
		}
		if (data.cornerRadius) frameNode.cornerRadius = data.cornerRadius;

		// Auto Layout (Flexbox mapping)
		if (data.layoutMode && data.layoutMode !== "NONE") {
			frameNode.layoutMode = data.layoutMode; // 'HORIZONTAL' | 'VERTICAL'
			frameNode.paddingTop = data.paddingTop || 0;
			frameNode.paddingBottom = data.paddingBottom || 0;
			frameNode.paddingLeft = data.paddingLeft || 0;
			frameNode.paddingRight = data.paddingRight || 0;
			frameNode.itemSpacing = data.itemSpacing || 0;
			frameNode.primaryAxisAlignItems = data.primaryAxisAlignItems || "MIN";
			frameNode.counterAxisAlignItems = data.counterAxisAlignItems || "MIN";

			// Auto sizing based on content
			frameNode.primaryAxisSizingMode = "AUTO";
			frameNode.counterAxisSizingMode = "AUTO";
		}

		// Process Children Recursively
		if (data.children && data.children.length > 0) {
			for (const childData of data.children) {
				const childNode = await createFigmaNode(childData, frameNode);
				if (childNode) {
					frameNode.appendChild(childNode);
				}
			}
		}

		node = frameNode;
	}

	// Positioning for Absolute/Standard layout
	if (
		data.x !== undefined &&
		data.y !== undefined &&
		parentNode &&
		(!("layoutMode" in parentNode) || parentNode.layoutMode === "NONE")
	) {
		node.x = data.x;
		node.y = data.y;
	}

	// Handle Box Shadow
	if (data.effects && data.effects.length > 0) {
		node.effects = data.effects;
	}

	return node;
}

figma.ui.onmessage = async (msg) => {
	if (msg.type === "create-figma-nodes") {
		try {
			const parentData = msg.data;
			const rootNode = await createFigmaNode(parentData);

			if (rootNode) {
				figma.currentPage.appendChild(rootNode);
				figma.currentPage.selection = [rootNode];
				figma.viewport.scrollAndZoomIntoView([rootNode]);
			}

			figma.notify("✅ Code successfully converted to Figma!");
		} catch (e) {
			console.error(e);
			figma.notify("⚠️ Error converting code. Check console.", { error: true });
		}
	}

	if (msg.type === "resize") {
		figma.ui.resize(msg.width, msg.height);
	}
};
