// Show the UI with support for Figma's theme colors
figma.showUI(__html__, { width: 280, height: 260, themeColors: true });

// Helper to convert Hex to RGB scale (0-1) used by Figma
function hexToRgb(hex) {
	const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
	return result
		? {
				r: parseInt(result[1], 16) / 255,
				g: parseInt(result[2], 16) / 255,
				b: parseInt(result[3], 16) / 255,
			}
		: null;
}

figma.ui.onmessage = (msg) => {
	if (msg.type === "apply-multiply") {
		const { hex, alpha } = msg;
		const rgb = hexToRgb(hex);

		if (!rgb) {
			figma.notify("Invalid color selected.");
			return;
		}

		const selection = figma.currentPage.selection;
		if (selection.length === 0) {
			figma.notify("Please select an image or vector layer first.");
			return;
		}

		let appliedCount = 0;

		for (const node of selection) {
			// Stricter TypeScript checks to ensure the node supports the properties we need
			if (
				"fills" in node &&
				"isMask" in node &&
				"blendMode" in node &&
				node.parent
			) {
				if (node.fills === figma.mixed) {
					figma.notify("Skipped layer with mixed fills.");
					continue;
				}

				const parent = node.parent;

				// Prevent crashes when trying to modify layers inside a Component Instance
				if (parent.type === "INSTANCE") {
					figma.notify(
						`Skipped "${node.name}" (cannot modify layers inside a Component Instance).`,
					);
					continue;
				}

				const index = parent.children.indexOf(node);

				// 1. Create Mask Node (bottom layer)
				const maskNode = node.clone();
				if ("isMask" in maskNode) maskNode.isMask = true;
				maskNode.name = `${node.name} (Alpha Mask)`;
				// Remove strokes and effects from the mask so they don't double-render
				if ("strokes" in maskNode) maskNode.strokes = [];
				if ("effects" in maskNode) maskNode.effects = [];

				// 2. Create Visible Image Node (middle layer)
				const imageNode = node.clone();

				// 3. Create Color Overlay Node (top layer)
				const overlayNode = node.clone();
				overlayNode.name = "Multiply Color";
				if ("fills" in overlayNode) {
					overlayNode.fills = [
						{
							type: "SOLID",
							color: rgb,
							opacity: alpha / 100,
						},
					];
				}

				// Remove strokes and effects from the overlay too
				if ("strokes" in overlayNode) overlayNode.strokes = [];
				if ("effects" in overlayNode) overlayNode.effects = [];
				if ("blendMode" in overlayNode) overlayNode.blendMode = "MULTIPLY";

				// Insert into the scene graph exactly where the old node was
				parent.insertChild(index, maskNode);
				parent.insertChild(index + 1, imageNode);
				parent.insertChild(index + 2, overlayNode);

				// Group them to isolate the mask clipping
				const group = figma.group([maskNode, imageNode, overlayNode], parent);
				group.name = `${node.name} (Multiply Overlay)`;

				// Note: Groups do not have their own constraints in Figma, so the previous
				// group.constraints logic was removed to fix TypeScript compilation errors.
				// The cloned children will automatically retain their original constraints!

				// Remove the original unmodified node
				node.remove();
				appliedCount++;
			}
		}

		if (appliedCount > 0) {
			figma.notify(`Applied multiply overlay to ${appliedCount} layer(s).`);
		} else {
			figma.notify("No valid layers found to apply overlay.");
		}
	}
};
