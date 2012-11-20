<form xmlns:py="http://purl.org/kid/ns#"
    name="${name}"
    method="${method}"
    py:attrs="form_attrs" width="100%">

    <div py:for="field in hidden_fields"
         py:replace="field.display(value_for(field), **params_for(field))" />

    <table cellpadding="0" cellspacing="0" width="45%">
        <tr>
            <td colspan="3">
                Tip: <a href="${tg.url('/login')}">Login</a> to impact how quickly this update gets pushed or unpushed.
            </td>
        </tr>
    </table>
</form>
