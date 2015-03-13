ifndef PIKE
 PIKE=pike
endif

doc:
	$(PIKE) -x extract_autodoc --root MailChimp.pmod lib/MailChimp.pmod/module.pmod
	$(PIKE) -x autodoc_to_html lib/MailChimp.pmod/module.pmod.xml documentation.html
